require 'aws-sdk'
require 'securerandom'
# Transport that stores to S3. Uses an archived_s3_key attribute.
module RailsArchiver
  module Transport
    class S3 < Base

      def s3_client
        option_hash = @options[:region] ? {:region => @options[:region]} : {}
        Aws::S3::Client.new(option_hash)
      end

      # Gzips the file, returns the gzipped filename
      def gzip(filename)
        output = `gzip --force #{filename.shellescape} 2>&1`

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
        s3_key = "#{@options[:base_path]}/#{file_path}.gz"
        Dir.mktmpdir do |dir|
          json_filename = "#{dir}/#{file_path}"
          @logger.info('Writing hash to JSON')
          File.write(json_filename, json)
          @logger.info('Zipping file')
          filename = gzip(json_filename)
          @logger.info("Uploading file to #{s3_key}")
          s3_client.put_object(:bucket => @options[:bucket_name],
                        :key => s3_key,
                        :body => File.open(filename))
        end
        s3_key
        @model.update_attributes(:archived_s3_key, s3_key)
      end

      def retrieve_archive
        Dir.mktmpdir do |dir|
          filename = "#{dir}/#{@model.id}.json"
          s3_client.get_object(
            :response_target => "#{filename}.gz",
            :bucket => @options[:bucket_name],
            :key => @model.archived_s3_key)
          @logger.info('Unzipping file')
          gzip("#{filename}.gz")
          @logger.info('Parsing JSON')
          JSON.parse(File.read(filename))
        end
      end


    end
  end
end