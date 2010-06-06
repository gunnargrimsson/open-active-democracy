class ActiveRecord::Base
  def self.retry_mysql_error(tries=3, &b)
    count = 0
    begin
      count += 1
      return b.call
    rescue Mysql::Error
      if count < tries
        sleep(0.1 * count)
        retry
      end
      raise
    end
  end
end