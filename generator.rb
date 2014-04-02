# -*- coding: utf-8 -*-
require 'mechanize'
require 'erb'
require 'ostruct'

module UserAgent

  UA_URL = "http://www.au.kddi.com/developer/android/kishu/ua/"
  DOCOMO_URL = "http://spec.nttdocomo.co.jp/spmss/"
  DOCOMO_BASE = "http://spec.nttdocomo.co.jp"
  SOFTBANK_URL = "https://www.support.softbankmobile.co.jp/partner/smp_info/smp_info_search_t.cfm"
  SOFTBANK_SEARCH_URL = "/partner/smp_info/smp_info_search_r.cfm"

  module_function

  def use_parallel
    require 'parallel'
  end

  def use_parallel?
    defined?(Parallel)
  end

  def each(enums, &block)
    if use_parallel?
      Parallel.each(enums, :in_threads => 20, &block)
    else
      enums.each &block
    end
  end

  def client
    @client ||= Mechanize.new{|a| a.ssl_version, a.verify_mode = 'SSLv3', OpenSSL::SSL::VERIFY_NONE}
  end

  def au
    result = []
    index = client.get UA_URL
    tables = index.search("table")
    tables.each {|t|
      trs = t.search("tr").tap { |this| this.shift }

      trs.each {|tr|
        tds = tr.search("td")
        next if tds.size == 2 and !tds.last["colspan"]

        result << [
          tds.first.text,
          tds.last.text.gsub("\r\n", " ").gsub(/\(注.*\)/, "")
        ]
      }
    }
    result
  end

  def docomo
    result = []
    page = client.get DOCOMO_URL

    links = page.search("td a")
    links.pop
    each(links) {|l|
      name = l.text
      spec = client.get DOCOMO_BASE + l["href"]

      ua = spec.at("th:contains('ユーザエージェント')").parent.text
        .split(/\P{ASCII}/)
        .select {|i| !["", "Chrome"].include?(i.strip) }
        .first.strip.chomp '"'
      ua.chop!.chomp! ' "' if ua[-2] == " "

      result << [name, ua]
    }
    result
  end

  def softbank
    page = client.get SOFTBANK_URL
    form = page.forms[2]
    payload = Hash[ form.fields.map {|f| [f.name, f.value]} ]
    info = client.post SOFTBANK_SEARCH_URL, payload

    heads = info.search("th.head")

    names = heads[6..-1].map{
      |x| x.text.gsub(/\P{ASCII}/, " ").chomp " "
    }

    uas = info.at("th:contains('User Agent')").parent.search("td").map {|td|
      td.text.strip
    }

    names.zip(uas)
  end

  def all
    if use_parallel?
      result = Parallel.map([:au, :docomo, :softbank], :in_processes => 2) {|x|
        [x, send(x)]
      }
      Hash[result]
    else
      {:au => au, :docomo => docomo, :softbank => softbank}
    end
  end
end

# use parallel => 38sec
# otherwise    => 1min 41sec
#
# Typhoeus maybe faster.
# http://typhoeus.github.io/
UserAgent.use_parallel
Encoding.default_external = "UTF-8"
ns = OpenStruct.new :company_uas => UserAgent.all
template = ERB.new(File.read("template.html.erb"))
File.open("index.html","w") << template.result(ns.instance_eval { binding })
