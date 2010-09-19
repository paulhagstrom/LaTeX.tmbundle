# encoding: UTF-8

require ENV["TM_SUPPORT_PATH"] + "/lib/tm/executor"
require ENV["TM_SUPPORT_PATH"] + "/lib/tm/save_current_document"

require ENV["TM_SUPPORT_PATH"] + "/lib/escape"
require ENV["TM_SUPPORT_PATH"] + "/lib/exit_codes"

class TexMate

  def initialize
    @stack = []
    @highest_warning = 0
    @printing_an_error = false
  end

  def update_current_file(line)
    # read greedily all matches
    while true
      # empty
      if line =~ /^\s*\(([^\n\(\)]*?)\)(.*)/
        line = $2
        next
      # closing
      elsif line =~ /^\s*\)(.*)/
        @stack.pop
        line = $1
        next
      # opening (may start anywhere)
      # Edit (Paul Hagstrom)
      # elsif line =~ /\((\/[^\n\(\)]*?)(?:\s*\[\d+\])?((?: |\n|\(|$).*)/
      # Risky perhaps, but I've removed the possibility that the filename ends at a space,
      # so that it will link to log files with a space in the name of a containing folder.
      # Works ok in the simple case, I don't know whether it will fail in more complex cases.
      elsif line =~ /\((\/[^\n\(\)]*?)(?:\s*\[\d+\])?((?:\n|\(|$).*)/
        @stack.push($1)
        line = $2
        next
      end
      break
    end
  end

  def current_file
    @stack[-1]
  end

  def link_to_error(file, num, message)
    return "<p><a href=\"txmt://open?url=file://#{e_url(file)}&line=#{num}\">#{File.basename file}#{num.nil? ? "" : ":"+num.to_s}</a> #{message}</p>"
  end

  def parse(line, type)
    @printing_an_error = true if line =~ /^!(?!\s*==>)/
    update_current_file(line) unless @printing_an_error

    file = current_file || ENV["TM_FILEPATH"]
    raise if file[0].nil?
    if not file.nil? and file[0].chr == "."
      file = ENV["TM_DIRECTORY"] + file[1..-1]
    end

    line.strip!
    if line =~ /^!(?!\s*==>)/
      link_to_error(file,line.slice(/lines? (\d+)/,1),line)
    elsif line =~ /^.*Warning: (.*)/
      @highest_warning = 2 if @highest_warning < 2
      message = $1
      link_to_error(file,line.slice(/lines? (\d+)/,1),message)
    elsif line =~ /^((?:Und|Ov)erfull.*)/
      @highest_warning = 1 if @highest_warning < 1
      message = $1
      link_to_error(file,line.slice(/lines? (\d+)/,1),message)
    elsif line =~ /^[^:]+:(\d+): (.*)/
      link_to_error(file,$1,$2)
    elsif line =~ /^l\.(\d+)(.*)/
      @printing_an_error = false
      link_to_error(file,$1,$2)
    elsif line =~ /^-->(.*)$/
      "<h4>#{$1}…</h4>"
    elsif line =~ /^-+$/
      "<hr/>\n"
    elsif @printing_an_error
      nil # returning nil lets Executor print the line
    else
      ''  # returning an empty string "" causes Executor to do nothing.
    end
  end

  def run(clean=false)

    ENV["TM_LATEX_DEFAULT_FORMAT"] ||= ENV["TM_BUNDLE_SUPPORT"] + "/lib/tmdefault.ltx"
    ENV["TM_LATEX"] ||= (`grep -c fontspec #{ENV["TM_FILEPATH"]}`.to_i > 0 ? 'xelatex' : 'pdflatex')
    ENV["TM_LATEX_FLAGS"] ||= nil
    ENV["TM_LATEX_CLEAN_FIRST"] = 'true' if clean

    TextMate.save_current_document("tex")

    # we need to save the sync info *before* we call
    # make_project_master_current_document or we will
    # sync to a line in the project master instead of
    # the current file.

    current_line=ENV["TM_LINE_NUMBER"]
    current_file=ENV["TM_FILEPATH"]

    TextMate::Executor.make_project_master_current_document

    p = Pathname(ENV["TM_FILEPATH"])
    pdf = ENV["TM_FILEPATH"].gsub(/#{p.extname}$/, ".pdf")

    engine = ENV["TM_LATEX"]
    args = [engine, ENV["TM_LATEX_FLAGS"], ENV["TM_FILEPATH"]].compact

    opts = {:verb => "Typesetting", :version_regex => /\A(.*)$\n?((?:.|\n)*)/}

    TextMate::Executor.run(args, opts) { |line, type| ENV.has_key?("TM_LATEX_DEBUG") ? nil : parse(line, type) }

    if $?.nil? or $?.exitstatus == 0
      if File.exists?(pdf) and not ENV["TM_FILEPATH"] =~ /.*-preamble.tex/
        Process.detach fork {
          `/usr/bin/osascript -e '
          set thePDF to "#{pdf}"
          try
            tell application "Skim"
              if (count of (documents whose path is thePDF)) = 0 then
                open thePDF
              else
                revert (documents whose path is thePDF)
              end if
              activate
              tell front document to go to TeX line #{current_line} from "#{current_file}" showing reading bar true
            end tell
          on error
            tell application "Preview"
              open thePDF
            end tell
          end try'`
        }
      end
      # sleep(5)
      TextMate::exit_discard if (ENV["TM_LATEX_WARN_LEVEL"].to_i || 0) >= @highest_warning
    else
      TextMate::exit_show_html
    end
  end

  def self.run(clean=false)
    TexMate.new.run(clean)
  end

end
