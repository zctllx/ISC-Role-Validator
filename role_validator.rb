require 'csv'
require 'optparse'

options = {}

#Define default file in the case where option -f is null
defaultFile = "Carga RBAC 07-08-2025"
options = { file: defaultFile }

#Define output file 
def generate_error_filename(file_path)
  name = File.basename(file_path, File.extname(file_path))
  "ERRORS REPORT - #{name}.txt"
end

# Columns
COLUMNS = ["operation", "name", "description", "disabled", "owner", "accessProfile", "entitlements", "requestable", "approversList", "denialCommentsRequired", "commentsRequired", "revokeApprovalSchemes", "tags", "segments"]
REQUIRED_COLUMNS = ["operation", "name", "description", "owner"]


OptionParser.new do |opts|
  opts.banner = "ruby script.rb -f FILE_PATH"
  opts.on("-f", "--file FILE", "Path to CSV file") do |file|
    options[:file] = file
  end
end.parse!

puts "Reading file: #{options[:file]}"

###############################################################################################################
## VALIDATIONS

def verifyRequiredColumns(header, requiredColumns)
  missingColumns = requiredColumns - header
  if missingColumns.empty?
    true
  else
    ["[ERROR] The following required columns are missing: #{missingColumns.join(', ')}"]
  end
end

def validate_row(line, index)
  errors = []
  line_n = index + 2
  name = line["name"] || "<no name>"

  # operation = createRole
  op = line["operation"]&.strip
  if op != "createRole"
    errors << "[Line #{line_n}] #{name}: The 'operation' column value is invalid \"#{op}\", expected \"createRole\""
  end

  # Booleans: true, false or null
  ["disabled", "requestable", "revokeCommentsRequired", "commentsRequired"].each do |field|
    value = line[field]&.strip
    unless value.nil? || value == "" || %w[true false].include?(value.downcase)
      errors << "[Line #{line_n}] #{name}: The column '#{field}' value is invalid \"#{value}\" - expected: true, false or null"
    end
  end

  # values parsing by ;
  ["approvalScheme", "revokeApprovalScheme", "accessProfiles"].each do |field|
    value = line[field]&.strip
    next if value.nil? || value == ""
    unless value.split(";").all? { |v| !v.strip.empty? }
      errors << "[Line #{line_n}] #{name}: The column '#{field}' value is invalid or contains unexpected format - \"#{value}\", expected values separate by ';'"
    end
  end

  # entitlements → source:attribute:value separados por ;
  ent = line["entitlements"]&.strip
  unless ent.nil? || ent.split(";").all? { |e| e.strip.match?(/^[^:]+:[^:]+:.+$/) }
    errors << "[Line #{line_n}] #{name}: The column 'entitlements' value is invalid \"#{ent}\" - expected: source:attribute:value"
  end

  [errors.empty?, errors]
end

def verifyValuesLineByLine(lines)
  errors = []
  lines.each_with_index do |line, index|
    valid, line_errors = validate_row(line, index)
    name = line["name"] || "<no name>"
    if valid
      puts "\e[32m[Success] Line #{index + 2} - #{name}\e[0m"
    else
      puts "\e[31m[ERROR] Line #{index + 2} - #{name}\e[0m"
      errors.concat(line_errors)
    end
  end
  errors.empty? ? true : errors
end

###############################################################################################################
## EXECUTION

begin
  lines = CSV.read(options[:file], headers: true).map(&:to_h)
  header = lines.first&.keys || []

  # verify required columns
  validColumns = verifyRequiredColumns(header, REQUIRED_COLUMNS)

  if validColumns != true
    # header with error will write a file and end proccess
    error_file = generate_error_filename(options[:file])
    File.open(error_file, "w") do |f|
      f.puts "[HEADER VALIDATION ERRORS - #{Time.now}]\n\n"
      validColumns.each { |e| f.puts e }
    end
    puts "\e[31m[ERROR] Required columns are missing. See '#{error_file}'\e[0m"
    exit 1
  end

  # verify lines
  result = verifyValuesLineByLine(lines)

  if result == true
    puts "\n\e[32m[SUCCESS] The CSV file is complete and correctly formated.\e[0m"
  else
    error_file = generate_error_filename(options[:file])
    File.open(error_file, "w") do |f|
      f.puts "[ROW VALIDATION ERRORS - #{Time.now}]\n\n"
      result.each { |e| f.puts e }
    end
    puts "\n\e[31m[ERROR] Validation failed. Errors were found in the file, see '#{error_file}' for details.\e[0m"
  end

rescue Errno::ENOENT
  puts "\e[31m[ERROR] File '#{options[:file]}' not found or does not exist.\e[0m"
  exit 1
end
