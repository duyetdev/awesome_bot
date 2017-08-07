require 'awesome_bot/check'
require 'awesome_bot/output'
require 'awesome_bot/result'
require 'awesome_bot/version'
require 'awesome_bot/write'

# Command line interface
module AwesomeBot
  CLI_OPT_ALLOW_DUPE = 'allow_dupe'
  CLI_OPT_ALLOW_REDIRECT = 'allow_redirect'
  CLI_OPT_ALLOW_SSL = 'allow_ssl'
  CLI_OPT_ALLOW_TIMEOUT = 'allow_timeout'
  CLI_OPT_BASE_URL = 'base_url'
  CLI_OPT_ERRORS = 'errors'
  CLI_OPT_FILES = 'files'
  CLI_OPT_REQUEST_DELAY = 'delay'

  class << self
    def cli()
      require 'optparse'

      ARGV << '-h' if ARGV.empty?

      options = {}
      ARGV.options do |opts|
        opts.banner = "Usage: #{PROJECT} [file or files] \n"\
                      "       #{PROJECT} [options]"

        opts.on('-f', '--files [files]',           Array,     'Comma separated files to check')                  { |val| options[CLI_OPT_FILES] = val }
        opts.on('-a', '--allow [errors]',          Array,     'Status code errors to allow')                     { |val| options[CLI_OPT_ERRORS] = val }
        opts.on('--allow-dupe',                    TrueClass, 'Duplicate URLs are allowed')                      { |val| options[CLI_OPT_ALLOW_DUPE] = val }
        opts.on('--allow-ssl',                     TrueClass, 'SSL errors are allowed')                          { |val| options[CLI_OPT_ALLOW_SSL] = val }
        opts.on('--allow-redirect',                TrueClass, 'Redirected URLs are allowed')                     { |val| options[CLI_OPT_ALLOW_REDIRECT] = val }
        opts.on('--allow-timeout',                 TrueClass, 'URLs that time out are allowed')                  { |val| options[CLI_OPT_ALLOW_TIMEOUT] = val }
        opts.on('--base-url [base url]',           String,    'Base URL to use for relative links')              { |val| options[CLI_OPT_BASE_URL] = val }
        opts.on('-d', '--request-delay [seconds]', Integer,   'Set request delay')                               { |val| options[CLI_OPT_REQUEST_DELAY] = val }
        opts.on('-t', '--set-timeout [seconds]',   Integer,   'Set connection timeout')                          { |val| options['timeout'] = val }
        opts.on('--skip-save-results',             TrueClass, 'Skip saving results')                             { |val| options['no_results'] = val }
        opts.on('--validate-markdown',             TrueClass, 'Validate Markdown (find space missing in links)') { |val| options['markdown'] = val }
        opts.on('-w', '--white-list [urls]',       Array,     'Comma separated URLs to white list')              { |val| options['white_list'] = val }

        opts.on_tail("--help") do
          puts opts
          exit
        end
        opts.parse!
      end

      files = options[CLI_OPT_FILES]
      if files.nil?
        files = []
        ARGV.each do |a|
          files.push a if a !~ /^--.*/
        end
      end

      summary = {}
      files.each do |f|
        summary[f] = cli_process(f, options)
      end

      if summary.count>1
        puts "\nSummary"

        largest = 0
        summary.each do |k, v|
          s = k.size
          largest = s if s>largest
        end

        summary.each do |k, v|
          k_display = "%#{largest}.#{largest}s" % k
          puts "#{k_display}: #{v}"
        end
      end

      summary.each { |k, v| exit 1 unless v==STATUS_OK }
    end

    def cli_process(filename, options)
      begin
        untrusted = File.read filename
        content = untrusted.encode('UTF-16', :invalid => :replace, :replace => '').encode('UTF-8')
      rescue => error
        puts "File open error: #{error}"
        return error
      end

      puts "> Checking links in #{filename}"
      puts output_summary(options)

      threads = options[CLI_OPT_REQUEST_DELAY] == nil ? 10 : 1
      r = check(content, options, threads) do |o|
        print o
      end

      digits = number_of_digits content
      unless r.white_listed.nil?
        puts "\n> White listed:"
        o = order_by_loc r.white_listed, content
        o.each_with_index do |x, k|
          temp, _ = output(x, k, pad_list(o), digits)
          puts temp
        end
      end

      no_results = options['no_results']
      no_results = false if no_results.nil?

      allow_redirect = options[CLI_OPT_ALLOW_REDIRECT]
      allow_redirect = false if allow_redirect.nil?

      allow_ssl = options[CLI_OPT_ALLOW_SSL]
      allow_ssl = false if allow_ssl.nil?

      allow_timeout = options[CLI_OPT_ALLOW_TIMEOUT]
      allow_timeout = false if allow_timeout.nil?

      options[CLI_OPT_ALLOW_REDIRECT] = allow_redirect
      options[CLI_OPT_ALLOW_SSL] = allow_ssl
      options[CLI_OPT_ALLOW_TIMEOUT] = allow_timeout

      if r.success(options)
        puts 'No issues :-)'
        write_results(filename, r, no_results)
        write_markdown_results(filename, nil, no_results)
        return STATUS_OK
      else
        puts "\nIssues :-("

        filtered_issues = output_filtered(content, r, options)
        write_results(filename, r, no_results)
        filtered = write_results_filtered(filename, filtered_issues, no_results)
        write_markdown_results(filename, filtered, no_results)

        return 'Issues'
      end
    end
  end # class
end
