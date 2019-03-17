require 'shellwords'

module Danger
  # Lint Haskell files inside your project using [HLint](https://github.com/ndmitchell/hlint)
  #
  # @example Lint a list of files
  #
  #          danger_hlint.lint(["Lib.hs"], inline_mode: true:
  #
  # @see  blender/danger-hlint
  # @tags hlint, haskell
  #
  class DangerHlint < Plugin
    # The list of suggestions found by hlint in JSON format
    #
    # @return   [String]
    attr_accessor :suggestions

    # The list of warnings found by hlint in JSON format
    #
    # @return [String]
    attr_accessor :warnings

    # The list of errors found by hlint in JSON format
    #
    # @return [String]
    attr_accessor :errors

    # Runs hlint on a list of files
    #
    # @return  [void]
    def lint(files, inline_mode = false, options = {})
      final_options = options.merge(json: true)

      WithResult = Struct.new(:file, :result)
      
      issues = files
               .map { |file| Shellwords.escape(file) }
               .map { |file| WithResult(file, `hlint #{file} #{to_hlint_options(final_options)} 2>/dev/null`) }
               .reject { |s| s.result == '' }
               .map { |lint_result| WithResult(lint_result.file, JSON.parse(lint_result.result).flatten) }
               .map { |result| result.result }
               .flatten

      # short_commits = git.commits.map { |commit| commit.to_s[0,8] }
      # commit_search = "'(#{short_commits.join "|"})'"
      # changed_lines = `git annotate #{file} | grep -En #{commit_search} | grep -o -E '^[0-9]+'`.split.map { |s| s.to_i }
     

      self.suggestions = issues.select { |issue| issue['severity'] == 'Suggestion' }
      self.warnings = issues.select { |issue| issue['severity'] == 'Warning' }
      self.errors = issues.select { |issue| issue['severity'] == 'Error' }

      if inline_mode
        # Reprt with inline comment
        send_inline_comment(suggestions, 'warn')
        send_inline_comment(warnings, 'warn')
        send_inline_comment(errors, 'fail')

      else
        # Report if any suggestions, warnings or errors
        if suggestions.count > 0 || warnings.count > 0 || errors.count > 0
          message = "### hlint found issues\n\n"
          message << markdown_issues(warnings, 'Suggestions') unless suggestions.empty?
          message << markdown_issues(warnings, 'Warnings') unless warnings.empty?
          message << markdown_issues(errors, 'Errors') unless errors.empty?
          markdown message
        end
      end
    end

    def markdown_issues(results, heading)
      message = "#### #{heading}\n\n"

      message << "File | Line  | Hint | Found | Suggested\n"
      message << "| --- | ----- | ----- | ----- | ----- |\n"

      results.each do |r|
        filename = r['file'].split('/').last
        line = r['startLine']
        hint = r['hint']
        from = r['from'].gsub("\n", '<br />')
        to   = r['to'].gsub("\n", '<br />')

        message << "#{filename} | #{line} | #{hint} | #{from} | #{to}\n"
      end

      message
    end

    def send_inline_comment(results, method)
      dir = "#{Dir.pwd}/"
      results.each do |r|
        filename = r['file'].gsub(dir, '')

        message = "Found #{r['hint']}\n\n```haskell\n#{r['from']}\n```"

        if !r['to'].nil?
          prompt = r['severity'] == 'Suggestion' || r['severity'] == 'Warning' ? 'Why Not' : ''
          prompt = r['severity'] == 'Error' ? 'Error description' : prompt

          message <<=  "\n\n #{prompt} \n\n ```haskell\n#{r['to']}\n```"
        end

        send(method, message, file: filename, line: r['startLine'])
      end
    end

    def to_hlint_options(options = {})
      options.
        # filter not null
        reject { |_key, value| value.nil? }.
        # map booleans arguments equal true
        map { |key, value| value.is_a?(TrueClass) ? [key, ''] : [key, value] }.
        # map booleans arguments equal false
        map { |key, value| value.is_a?(FalseClass) ? ["no-#{key}", ''] : [key, value] }.
        # replace underscore by hyphen
        map { |key, value| [key.to_s.tr('_', '-'), value] }.
        # prepend '--' into the argument
        map { |key, value| ["--#{key}", value] }.
        # reduce everything into a single string
        reduce('') { |args, option| "#{args} #{option[0]} #{option[1]}" }.
        # strip leading spaces
        strip
    end

    private :send_inline_comment, :to_hlint_options, :markdown_issues
  end
end
