require "json"
require "open3"

module Fontcustom
  module Generator
    class Font
      include Utility

      attr_reader :manifest

      def initialize(manifest)
        @manifest = Fontcustom::Manifest.new manifest
        @options = @manifest.get :options
      end

      def generate
        create_output_dirs
        delete_old_fonts
        set_glyph_info
        create_fonts
      end

      private

      def create_output_dirs
        dirs = @options[:output].values.uniq
        dirs.each do |dir|
          unless File.directory? dir
            empty_directory dir, :verbose => false
            say_message :create, dir
          end
        end
      end

      def delete_old_fonts
        @manifest.delete :fonts
      end

      def set_glyph_info
        manifest_glyphs = @manifest.get :glyphs
        codepoint, glyphs = if ! manifest_glyphs.empty?
          codepoints = manifest_glyphs.values.map { |data| data[:codepoint] }
          codepoint = codepoints.max + 1

          glyphs = {}
          basename = @options[:input][:vectors]
          manifest_glyphs.each do |name, glyph|
            source = glyph[:source]
            file = if ! source.empty?
               source
            else
              "#{basename}/#{name}.svg"
            end
            glyphs[name.to_sym] = { :source => file }
          end

          [ codepoint, glyphs ]
        else
          glyphs = {}
          files = Dir.glob File.join(@options[:input][:vectors], "*.svg")
          files.each do |file|
            name = File.basename file, ".svg"
            name = name.strip.gsub(/\W/, "-")
            glyphs[name.to_sym] = { :source => file }
            if File.read(file).include? "rgba"
              say_message :warn, "`#{file}` contains transparency and will be skipped."
            end
          end

          # Offset to work around Chrome Windows bug
          # https://github.com/FontCustom/fontcustom/issues/1
          [ 0xf100, glyphs ]
        end

        # Dir.glob returns a different order depending on ruby
        # version/platform, so we have to sort it first
        glyphs = Hash[glyphs.sort_by { |key, val| key.to_s }]
        glyphs.each do |name, data|
          if manifest_glyphs.has_key? name
           data[:codepoint] = manifest_glyphs[name][:codepoint]
          else
            data[:codepoint] = codepoint
            codepoint = codepoint + 1
          end
        end
        @manifest.set :glyphs, glyphs
      end

      def create_fonts
        cmd = "fontforge -script #{Fontcustom.gem_lib}/scripts/generate.py #{@manifest.manifest}"
        stdout, stderr, status = Open3::capture3(cmd)
        stdout = stdout.split("\n")
        stdout = stdout[1..-1] if stdout[0] == "CreateAllPyModules()"

        debug_msg = " Try again with --debug for more details."
        if @options[:debug]
          messages = stderr.split("\n") + stdout
          say_message :debug, messages.join(line_break)
          debug_msg = ""
        end

        if status.success?
          @manifest.reload
          say_changed :create, @manifest.get(:fonts)
        else
          raise Fontcustom::Error, "`fontforge` compilation failed.#{debug_msg}"
        end
      end
    end
  end
end
