# coding: utf-8

def create_tags(row)
  tags = []
  tags << row[1]
  tags << row[2]
  tags << row[3]
  tags << row[4]
  tags << row[5]
  tags << row[6]
  tags.join(",")
end

def create_priority_from_row(row,current_user,partner)
  priority_name = row[0].mb_chars.slice(0..59)
  priority_tags = create_tags(row)
  point_name = row[7].mb_chars.slice(0..59)
  point_text = row[8].mb_chars.slice(0..499)
  point_link = row[9]
  
  begin
    Priority.transaction do
      @priority = Priority.new
      @priority.name = priority_name
      @priority.user = current_user
      @priority.ip_address = "127.0.0.1"
      @priority.issue_list = priority_tags
      @priority.partner_id = partner.id
      puts @priority.inspect
      @saved = @priority.save
      puts @saved

      if @saved
        @point = Point.new
        @point.user = current_user
        @point.priority_id = @priority.id
        @point.content = point_text
        @point.name = point_name
        @point.value = 1
        @point.website = point_link if point_link and point_link != ""
        @point.partner_id = partner.id
        puts @point.inspect
        @point_saved = @point.save
      end
      puts @point_saved
      if @point_saved
        if Revision.create_from_point(@point.id)
          @quality = @point.point_qualities.find_or_create_by_user_id_and_value(current_user.id,true)
        end      
      end
      raise "rollback" if not @point_saved or not @saved
    end
  rescue => e
    puts "ROLLBACK ERROR ON IMPORT"
    puts e.message
  end    
end

CODE_TO_SHORTNAME = {"AE"=>"uae", "LY"=>"lybia", "VA"=>"vatican",
                     "PS"=>"ps", "GB"=>"uk", "SY"=>"syria", "RU"=>"russia",
                     "MD"=>"moldova", "LA"=>"lao" }
namespace :utils do
  desc "Create BR categories"
  task :create_br_categories => :environment do
  end

  desc "Create partners from iso countries"
  task :create_partners_from_iso => :environment do
    Tr8n::IsoCountry.all.each do |country|
      p=Partner.new
      p.name = country.country_english_name
      p.geoblocking_enabled = true
      p.geoblocking_open_countries = country.code.downcase
      if CODE_TO_SHORTNAME[country.code]
        p.short_name = CODE_TO_SHORTNAME[country.code]
      else
        p.short_name = country.country_english_name.downcase.gsub(" ","-").gsub(",","").gsub("(","").gsub(")","").gsub("'","").gsub(",","").gsub(".","")
      end
      puts p.short_name
      p.iso_country_id = country.id
      p.save unless Partner.find_by_iso_country_id(country.id)
    end
  end

  desc "Dump database to tmp"
  task :dump_db => :environment do
    config = Rails.application.config.database_configuration
    current_config = config[Rails.env]
    abort "db is not mysql" unless current_config['adapter'] =~ /mysql/
    
    database = current_config['database']
    user = current_config['username']
    password = current_config['password']
    
    path = Rails.root.join("tmp","sqldump")
    filename = path.join("#{database}_#{Time.new.strftime("%d%m%y_%H%M%S")}.sql.gz")

    FileUtils.mkdir_p(path)
    command = "mysqldump --add-drop-table -u #{user} --password=#{password} #{database} | gzip > #{filename}"
    puts "Excuting #{command}"
    system command
  end

  desc "Archive processes"
  task(:archive_processes => :environment) do
      if ENV['current_thing_id']
        logg = "#{ENV['current_thing_id']}. log"
        puts "Archiving all processes except for thing: #{logg}"
        Process.find(:all).each do |c|
          puts c.external_info_3
          unless c.external_info_3.index(logg)
            puts "ARCHIVING"
            c.archived = true
            c.save
          end
        end
      end
  end

  desc "Backup"
  task(:backup => :environment) do
      filename = "skuggathing_#{Time.new.strftime("%d%m%y_%H%M%S")}.sql"
      system("mysqldump -u robert --password=X --force odd_dev_2 > /home/robert/#{filename}")
      system("gzip /home/robert/#{filename}")
      system("scp /home/robert/#{filename}.gz robert@where.is:backups/#{filename}.gz")
      system("rm /home/robert/#{filename}.gz")
  end

  desc "Delete Fully Processed Masters"
  task(:delete_fullly_processed_masters => :environment) do
      masters = ProcessSpeechMasterVideo.find(:all)
      masters.each do |master_video|
        puts "master_video id: #{master_video.id} all_done: #{master_video.process_speech_videos.all_done?} has_any_in_processing: #{master_video.process_speech_videos.any_in_processing?}"
        if master_video.process_speech_videos.all_done? and not master_video.process_speech_videos.any_in_processing?
          master_video_flv_filename = "#{Rails.root.to_s}/private/"+ENV['Rails.env']+"/process_speech_master_videos/#{master_video.id}/master.flv"
          if File.exist?(master_video_flv_filename)
            rm_string = "rm #{master_video_flv_filename}"
            puts rm_string
            system(rm_string)
          end
        end
      end
  end

  desc "Delete Not Valid Video Folders"
  task(:delete_not_valid_video_folders => :environment) do
      Dir.entries("public/development/process_speech_videos").each do |filename|
        next if filename=="." or filename==".."
        unless ProcessSpeechVideo.exists?(filename.to_i)
          puts "rm -r public/development/process_speech_videos/#{filename}"
        else
          puts "Keeping public/development/process_speech_videos/#{filename}"
        end
      end
  end

  desc "Explore broken videos"
  task(:explore_broken_videos => :environment) do
      masters = ProcessSpeechMasterVideo.find(:all)
      masters.each do |master_video|
        unless master_video.process_speech_videos.all_done? and not master_video.process_speech_videos.any_in_processing?
          master_video_flv_filename = "#{Rails.root.to_s}/private/"+ENV['Rails.env']+"/process_speech_master_videos/#{master_video.id}/master.flv"
          if File.exist?(master_video_flv_filename)
            puts "master_video id: #{master_video.id} all_done: #{master_video.process_speech_videos.all_done?} has_any_in_processing: #{master_video.process_speech_videos.any_in_processing?}"
            master_video.process_speech_videos.each do |video|
              puts "video id #{video.id} published #{video.published} #{video.title} in_processing #{video.in_processing} duration: #{video.duration_s} in: #{video.inpoint_s}"            
            end
            puts " "
          end
        end
      end
  end

  desc "Expoirt priority categories"
  task(:export_priority_categories => :environment) do
    csv_data = CSV.generate do |csv|
      csv << Category.all.collect {|c| "#{c.name} - #{c.id}"}
      csv << []
      csv << ["Priority name","Category id"]
      Priority.all.each do |p|
        if p.category
          csv << ["\"#{p.name.gsub("\"","")}\"",p.category.id]
        else
          csv << ["\"#{p.name.gsub("\"","")}\"",0]
        end
      end
    end
    puts csv_data
  end

  desc "Import priorities"
  task(:import_priorities => :environment) do
    @current_government = Government.last
    if @current_government
      @current_government.update_counts
      Government.current = @current_government
    end
    unless current_user = User.find_by_email("island@skuggathing.is")
      current_user=User.new
      current_user.email = "island@skuggathing.is"
      current_user.login = "Island.is"
      current_user.save(:validate => false)
    end
    f = File.open(ENV['csv_import_file'])
    partner = Partner.find_by_short_name(ENV['partner_short_name'])
    CSV.parse(f.read) do |row|
      puts row.inspect
      create_priority_from_row(row, current_user, partner)  
    end
  end
end
