$stack = []
$fragment = nil

def update_current_file(line)
  while true
    unless $fragment
      while line =~ /^ *\)(.*)/
        $stack.pop
        line = $1
      end
      if line =~ /\(([^\(\)\n]*?)(\s*\[\d+\])?\n?$/
        if line.length < 80
          $stack.push($1)
        else
          $fragment = $1
        end
      elsif line =~ /\(([^\(\)\n]*?)\s*\(/
        $stack.push($1)
      end
      break
    else
      if line =~ /^([^\(\)]*)\)(.*)/
        line = $2
      elsif line =~ /^([^\(\)]*)\((.*)/ or line =~ /^([^\(\)]*)(\n)?$/
        line = $2
        $stack.push($fragment+$1)
      else
        raise
      end
      $fragment=nil
    end
  end
  while line =~ /(.*\))\)$/
    $stack.pop
    line = $1
  end
end

def current_file
  $stack.pop while $stack[-1] == ""
  return $stack[-1]
end
