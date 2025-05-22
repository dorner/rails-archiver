# frozen_string_literal: true

module RailsArchiver
  module Utils
    # Utility module to retry a block of code in case of a deadlock.
    module DeadlockRetry
      class << self

        RETRY_COUNT = 2

        def wrap(&block)
          count = RETRY_COUNT
          begin
            ActiveRecord::Base.transaction(&block)
          rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
            raise if count <= 0

            Rails.logger.error("Error: #{e.message}. Retrying. #{count} attempts remaining")
            count -= 1

            sleep(Random.rand(5.0) + 0.5)

            retry
          end
        end
      end
    end
  end
end
