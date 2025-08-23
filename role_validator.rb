require 'csv'
require 'optparse'
require 'uri'
require 'json'
require 'net/http'

options = {}
config = JSON.parse(File.read('config.json'))
defaultFile = config['file'] 
options = { file: defaultFile }

def generate_error_filename(file_path)
  name = File.basename(file_path, File.extname(file_path))
  "ERRORS REPORT - #{name}.csv"
end

COLUMNS = ["operation", "name", "description", "disabled", "owner", "accessProfile", "entitlements", "requestable", "approversList", "denialCommentsRequired", "commentsRequired", "revokeApprovalSchemes", "tags", "segments"]
REQUIRED_COLUMNS = ["operation", "name", "description", "owner"]

OptionParser.new do |opts|
  opts.banner = "ruby script.rb -f FILE_PATH"
  opts.on("-f", "--file FILE", "Path to CSV file") { |file| options[:file] = file }
end.parse!

puts "Reading file: #{options[:file]}"

################### API FUNCTIONS ##############################

def getToken()
  config = JSON.parse(File.read('config.json'))
  uri = URI.parse("#{config["baseUrl"]}/oauth/token?grant_type=client_credentials&client_id=#{config["clientId"]}&client_secret=#{config["clientSecret"]}")
  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(request) }

  if response.code.to_i == 200
    JSON.parse(response.body)["access_token"]
  else
    raise "Failed to get access token: #{response.body}"
  end
end

def createHeader()
  header = {
    "Content-Type" => "application/json",
    "X-CSRF-Token" => "nocheck",
    "User-Agent"   => "spps-idn-bulk-configuration"
  }
  accessToken = getToken()
  if accessToken
    header["Authorization"] = "Bearer #{accessToken}"
    return header
  else
    raise "ERROR: Access Token is empty"
  end
end

def checkEntitlements(sourceName, attribute, entitlementName, config, header)
  endpoint = URI("#{config["baseUrl"]}/v2024/search")
  https = Net::HTTP.new(endpoint.host, endpoint.port)
  https.use_ssl = true

  body = {
    "indices": ["entitlements"],
    "query": {
      "query": "(value:\"#{entitlementName}\") AND (attribute:\"#{attribute}\") AND (source.name:\"#{sourceName}\")"
    }
  }

  request = Net::HTTP::Post.new(endpoint)
  header.each { |key, value| request[key] = value }
  request.body = body.to_json

  https.request(request)
end

################### EXECUTION ##############################

begin
  lines = CSV.read(options[:file], headers: true).map(&:to_h)
  header_csv = lines.first&.keys || []
  config = JSON.parse(File.read('config.json'))
  header_api = createHeader()
  error_rows = []

  # Verify required columns
  missing_cols = REQUIRED_COLUMNS - header_csv
  unless missing_cols.empty?
    puts "[ERROR] Required columns missing: #{missing_cols.join(', ')}"
    exit 1
  end

  # Process each CSV row
  lines.each_with_index do |line, index|
    line_n = index + 2
    entitlements = line["entitlements"]&.split(";") || []

    entitlements.each do |ent|
      source, attribute, name = ent.strip.split(":")

      next if source.nil? || attribute.nil? || name.nil?

      response = checkEntitlements(source, attribute, name, config, header_api)

      if response.code.to_i == 200
        puts "\e[32m[Success] Line #{line_n} - Entitlement '#{ent}' found\e[0m"
      else
        puts "\e[31m[FAIL] Line #{line_n} - Entitlement '#{ent}' NOT found (HTTP #{response.code})\e[0m"
        error_rows << { "line" => line_n, "entitlement" => ent, "status_code" => response.code }
      end
    end
  end

  # Save failed entitlements to CSV
  unless error_rows.empty?
    error_file = generate_error_filename(options[:file])
    CSV.open(error_file, "w") do |csv|
      csv << ["line", "entitlement", "status_code"]
      error_rows.each { |row| csv << row.values }
    end
    puts "\n\e[31m[INFO] #{error_rows.size} entitlements failed. See '#{error_file}'\e[0m"
  else
    puts "\n\e[32m[INFO] All entitlements validated successfully.\e[0m"
  end

rescue Errno::ENOENT
  puts "[ERROR] File '#{options[:file]}' not found."
  exit 1
end
