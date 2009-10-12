require ENV["TM_SUPPORT_PATH"] + '/lib/escape'
require 'pp'

def choices_for_selected_text
  
  selected_text = e_sn(ENV['TM_SELECTED_TEXT'] || '…')
  selected_text_display = "#{selected_text[0,10]}#{selected_text.length>10 ? "…" : ''}"
  
  choices = []
  
  # MATH MODE
  [["(", ")"], ["[", "]"]].each do |math_open, math_close|
    choices << {
      'display'=>"\\#{math_open} #{selected_text_display} \\#{math_close}",
      'match' => "\\#{math_open}",
      'insert' => " #{selected_text}$1 \\#{math_close}$0"}
  end

  # BEGIN / END
  choices << {
    'display'=>"\\begin{…} #{selected_text_display} \\end{…}",
    'match'=>'\begin{',
    'insert'=>"${1:…}}
	${2:#{selected_text}}
\\end{$1}$0",
    'children' => []}
  
  ## LIST ENVIRONMENTS
  ["itemize", "enumerate", "description", "list"].each do |env|
    choices[-1]['children'] << {
      'display'=>"\\begin{#{env}} #{selected_text_display} \\end{#{env}}",
      'match'  =>"\\begin{#{env}",
      'insert' =>"}
	${2:#{selected_text}}
\\end{#{env}}$0"
    }
  end
  
  ## DOCUMENT HEADINGS
  folds = ENV["TM_LATEX_NO_FOLD_COMMENTS"].nil?
  ["part", "chapter", "section", "paragraph"].each do |cmd|
    choices << {
      "display" => "\\#{cmd}{#{selected_text_display}}",
      "match"   => "\\#{cmd}{",
      "insert"  => "${1:#{selected_text}}}\\label{#{cmd}:${2:${1/\\\\\\w*|( )|[^\\w]/(?1:_)/g}}}#{folds ? " % (fold)" : ''}
	${3}
#{folds ? "% #{cmd}:$2 (end)" : ""}
$0"
    }
  end
  
  choices[-2]['children'] = ["subsection", "subsubsection"].collect do |cmd|
    { "display" => "\\#{cmd}{#{selected_text_display}}",
      "match"   => "\\#{cmd}{",
      "insert"  => "${1:#{selected_text}}}\\label{#{cmd}:${2:${1/\\\\\\w*|( )|[^\\w]/(?1:_)/g}}}#{folds ? " % (fold)" : ''}
	${3}
#{folds ? "% #{cmd}:$2 (end)" : ""}
$0"}
  end
  
  choices[-1]['children'] = ["subparagraph"].collect do |cmd|
    { "display" => "\\#{cmd}{#{selected_text_display}}",
      "match"   => "\\#{cmd}{",
      "insert"  => "${1:#{selected_text}}}\\label{#{cmd}:${2:${1/\\\\\\w*|( )|[^\\w]/(?1:_)/g}}}#{folds ? " % (fold)" : ''}
	${3}
#{folds ? "% #{cmd}:$2 (end)" : ""}
$0"}
  end
  
  return choices
end

puts pp choices_for_selected_text if __FILE__ == $0