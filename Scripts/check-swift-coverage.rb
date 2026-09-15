#!/usr/bin/env ruby

require "json"
require "open3"
require "set"

def capture(*command)
  output, error, status = Open3.capture3(*command)
  abort(error.empty? ? "Command failed: #{command.join(" ")}" : error) unless status.success?
  output
end

abort("Pass one or more SwiftPM coverage JSON files") if ARGV.empty?

coverage_paths = ARGV.map { |path| File.expand_path(path) }
Dir.chdir(File.expand_path("..", __dir__))
sources = Dir.glob("Sources/**/*.swift").sort.map { |path| File.expand_path(path) }.to_set
abort("No production Swift source files found") if sources.empty?

source_mtime = sources.map { |path| File.mtime(path) }.max
lines = {}
regions = {}

coverage_paths.each do |json_path|
  abort("Coverage JSON does not exist: #{json_path}") unless File.file?(json_path)

  configuration = File.dirname(File.dirname(json_path))
  binary = File.join(configuration, "PersistentKeyValueKitPackageTests.xctest/Contents/MacOS/PersistentKeyValueKitPackageTests")
  profile = File.join(configuration, "codecov/default.profdata")
  [binary, profile].each do |path|
    abort("Coverage artifact does not exist: #{path}") unless File.file?(path)
  end
  if source_mtime > File.mtime(binary) || File.mtime(binary) > File.mtime(profile) || File.mtime(binary) > File.mtime(json_path)
    abort("Coverage artifacts are stale: #{json_path}; rerun swift test --enable-code-coverage")
  end

  sources.each do |path|
    output = capture("xcrun", "llvm-cov", "show", binary, "-instr-profile=#{profile}", "-use-color=false", path)
    output.each_line do |line|
      match = line.match(/^\s*(\d+)\|\s*(\d+(?:\.\d+)?[kMGT]?)\|/)
      next unless match

      key = [path, match[1].to_i]
      lines[key] = lines.fetch(key, false) || match[2].to_f.positive?
    end
  end

  JSON.parse(File.read(json_path)).fetch("data").each do |data|
    data.fetch("functions").each do |function|
      function.fetch("regions").each do |region|
        path = File.expand_path(function.fetch("filenames")[region[5]])
        next unless sources.include?(path) && region[7] == 0

        key = [path, *region[0, 4]]
        regions[key] = regions.fetch(key, false) || region[4].positive?
      end
    end
  end
end

puts "Scope: all production Swift code; no coverage exclusions."
puts "Configurations: #{coverage_paths.map { |path| File.basename(File.dirname(File.dirname(path))) }.join(", ")}"
{ "lines" => lines, "regions" => regions }.each do |kind, entries|
  puts "#{kind}: #{entries.values.count(true)}/#{entries.length} covered"
  entries.reject { |_, covered| covered }.each do |key, _|
    path, line, *coordinates = key
    source_line = File.readlines(path)[line - 1]&.strip
    puts "UNCOVERED #{kind} #{path}:#{line} #{coordinates.join(":")} #{source_line}"
  end
end

abort("No executable production lines found") if lines.empty?
abort("No executable production regions found") if regions.empty?
exit(lines.values.all? && regions.values.all? ? 0 : 1)
