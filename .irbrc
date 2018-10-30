# load libraries
libraries = %w(rubygems pp irb ostruct open-uri benchmark irb/completion)
libraries.each do |lib|
  begin
    require lib
  rescue LoadError
    STDERR.puts "Can't loaded #{lib}."
  end
end

IRB.conf[:SAVE_HISTORY] = 10000
IRB.conf[:HISTORY_FILE] = File::expand_path("#{Dir.home}/.irb_history")
IRB.conf[:AUTO_INDENT] = true
IRB.conf[:USE_READLINE] = true
IRB.conf[:PROMPT][:ORIGINAL] = {
  PROMPT_I: '> ',
  PROMPT_S: "%l ",
  PROMPT_C: '* ',
  RETURN: "%s\n"
}

# prompt
require 'irb/completion'
IRB.conf[:PROMPT_MODE] = :ORIGINAL

# alias
alias q exit
