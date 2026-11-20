#!/usr/bin/env ruby

# Type-checks the Swift samples in Tests/DocumentationSamples against the built module, then verifies that every Swift
# code block in the README and release notes appears verbatim in one of those samples. API excerpts that quote a
# declaration are matched against Sources instead, and the package manifest snippet is exempt.

require "open3"

# Returns combined stdout and stderr, for diagnostics.
def capture(*command)
  output, status = Open3.capture2e(*command)
  [output, status.success?]
end

# Returns stdout only, so that warnings on stderr never contaminate a value. Stderr is reported when the command fails.
def capture_stdout(*command)
  output, error, status = Open3.capture3(*command)
  [status.success? ? output : error, status.success?]
end

def normalized_lines(text)
  text.lines.map(&:rstrip)
end

# Returns whether `block` appears as consecutive lines of `lines` at a single, consistent indentation.
def contains_block?(lines, block)
  first = block.first
  lines.each_index.any? do |start|
    candidate = lines[start]
    next false unless candidate.end_with?(first)

    indent = candidate.delete_suffix(first)
    next false unless indent.strip.empty?

    block.each_with_index.all? do |line, offset|
      sample_line = lines[start + offset]
      next false if sample_line.nil?

      line.empty? ? sample_line.strip.empty? : sample_line == indent + line
    end
  end
end

Dir.chdir(File.expand_path("..", __dir__))

output, success = capture("swift", "build")
abort(output) unless success
build_path, success = capture_stdout("swift", "build", "--show-bin-path")
abort(build_path) unless success
build_path = build_path.strip

samples = Dir.glob("Tests/DocumentationSamples/*.swift").sort
abort("No documentation samples found") if samples.empty?

failures = []

samples.each do |sample|
  # The native build system emits modules under `Modules`; Swift Build emits them in the bin path itself.
  output, success = capture(
    "xcrun", "swiftc", "-typecheck", "-module-name", "DocumentationSamples", "-swift-version", "6", "-warnings-as-errors",
    "-I", File.join(build_path, "Modules"), "-I", build_path, sample
  )
  failures << "#{sample} does not compile:\n#{output}" unless success
end

sample_lines = samples.map { |path| normalized_lines(File.read(path)) }
source_lines = Dir.glob("Sources/**/*.swift").sort.map do |path|
  normalized_lines(File.read(path)).map(&:strip).reject { |line| line.empty? || line.start_with?("//") }
end

documents = ["README.md", *Dir.glob("docs/release-notes/*.md").sort]
block_count = 0

documents.each do |document|
  File.read(document).scan(/^```swift\n(.*?)^```/m).each do |(code)|
    block = normalized_lines(code)
    block.pop while block.last&.empty?
    next if block.empty?

    block_count += 1
    next if sample_lines.any? { |lines| contains_block?(lines, block) }

    excerpt = block.map(&:strip).reject(&:empty?)
    next if source_lines.any? { |lines| contains_block?(lines, excerpt) }
    next if block.first.start_with?("dependencies: [")

    failures << "#{document} has a Swift block that is not in Tests/DocumentationSamples or Sources:\n#{block.join("\n")}"
  end
end

unless failures.empty?
  warn(failures.join("\n\n"))
  exit(1)
end

puts "Documentation samples passed (#{samples.length} sample files, #{block_count} Swift blocks)."
