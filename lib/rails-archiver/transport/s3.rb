require 'securerandom'
require 'tmpdir'

# Transport that stores to S3. Uses an archived_s3_key attribute if present.
module RailsArchiver
  module Transport
    class S3 < Base

      def s3_client
        option_hash = @options[:region] ? {:region => @options[:region]} : {}
        Aws::S3::Client.new(option_hash)
      end

      # Gzips the file, returns the gzipped filename
      def gzip(filename)
        output = `gzip #{filename.shellescape} 2>&1`

        raise output if $?.exitstatus != 0

        "#{filename}.gz"
      end

      def gunzip(filename)
        output = `gunzip --force #{filename.shellescape} 2>&1`

        raise output if $?.exitstatus != 0
      end

      def store_archive(hash)
        json = hash.to_json
        file_path = "#{@model.id}_#{SecureRandom.hex(8)}.json"
        base_path = @options[:base_path] ? "#{@options[:base_path]}/" : ''
        s3_key = "#{base_path}#{file_path}.gz"
        Dir.mktmpdir do |dir|
          json_filename = "#{dir}/#{file_path}"
          @logger.info('Writing hash to JSON')
          File.write(json_filename, json)
          @logger.info('Zipping file')
          filename = gzip(json_filename)
          @logger.info("Uploading file to #{s3_key}")
          _save_archive_to_s3(s3_key, filename)
        end
        if @model.respond_to?(:archived_s3_key)
          @model.update_attribute(:archived_s3_key, s3_key)
        end
        s3_key
      end

      # @param location [String]
      def retrieve_archive(location=nil)
        Dir.mktmpdir do |dir|
          s3_key = location
          filename = nil
          if @model
            if @model.respond_to?(:archived_s3_key)
              s3_key ||= @model.archived_s3_key
            end
            filename = "#{dir}/#{@model.id}.json"
          else
            filename = File.basename(s3_key)
          end
          _get_archive_from_s3(s3_key, "#{filename}.gz")
          @logger.info('Unzipping file')
          gunzip("#{filename}.gz")
          @logger.info('Parsing JSON')
          JSON.parse(File.read(filename))
        end
      end

      private

      def _get_archive_from_s3(s3_key, filename)
        s3_client.get_object(
          :response_target => filename,
          :bucket => @options[:bucket_name],
          :key => s3_key)
      end

      def _save_archive_to_s3(s3_key, filename)
          s3_client.put_object(:bucket => @options[:bucket_name],
                        :key => s3_key,
                        :body => File.open(filename))

      end
    end
  end
end
