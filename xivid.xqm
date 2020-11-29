(:~
 : --------------------------------
 : Xivid function module
 : --------------------------------
 :
 : Copyright (C) 2020 Reino Wijnsma
 :
 : This program is free software: you can redistribute it and/or modify
 : it under the terms of the GNU General Public License as published by
 : the Free Software Foundation, either version 3 of the License, or
 : (at your option) any later version.
 :
 : This program is distributed in the hope that it will be useful,
 : but WITHOUT ANY WARRANTY; without even the implied warranty of
 : MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 : GNU General Public License for more details.
 :
 : You should have received a copy of the GNU General Public License
 : along with this program.  If not, see <http://www.gnu.org/licenses/>.
 :
 : @author Reino Wijnsma (rwijnsma@xs4all.nl)
 : @see    https://github.com/Reino17/xivid
 :)

xquery version "3.0-xidel";
module namespace xivid = "https://github.com/Reino17/xivid/";

(:~
 : --------------------------------
 : Helper functions
 : --------------------------------
 :)

declare function xivid:m3u8-to-json($url as string?) as object()* {
  let $m3u8:=x:request(
        {"url":$url,"error-handling":"4xx=accept"}[url]
      )[doc[not(contains(.,"#EXT-X-SESSION-KEY:METHOD=SAMPLE-AES"))]],
      $m3u8Url:=if (string-length($m3u8/url) lt 512) then $m3u8/url else $url,
      $streams:=extract(
        $m3u8/doc,
        "#EXT-X-(?:MEDIA:TYPE=(?:AUDIO|VIDEO)|STREAM-INF).+?m3u8.*?$",
        0,"ms*"
      )
  return
  if (exists($m3u8) and not(exists($streams))) then {
    "id":"hls-1",
    "format":"m3u8[h264+aac]",
    "url":$m3u8Url
  } else (
    extract($m3u8/doc,"#EXT-X-MEDIA:TYPE=SUBTITLES.+")[.] ! {
      "id":"sub-1",
      "format":"m3u8[vtt]",
      "language":extract(.,"LANGUAGE=&quot;(.+?)&quot;",1),
      "url":resolve-uri(
        extract(.,"URI=&quot;(.+?)&quot;",1),
        $m3u8Url
      )
    },
    for $x at $i in $streams[contains(.,"PROGRESSIVE-URI")]
    let $br:=extract($x[1],"BANDWIDTH=(\d+)",1)
    group by $br
    count $i
    return {
      "id":"pg-"||$i,
      "format":"mp4[h264+aac]",
      "resolution":extract($x[1],"RESOLUTION=([\dx]+)",1),
      "bitrate":round($br div 1000)||"kbps",
      "url":extract($x[1],"URI=&quot;(.+mp4)(?:#.+)?&quot;",1)
    },
    {
      "id":"hls-0",
      "format":"m3u8[manifest]",
      "url":$m3u8Url
    }[url],
    for $x at $i in $streams
    let $br:=extract($x[1],"BANDWIDTH=(\d+)",1)
    group by $br
    count $i
    return {
      "id":"hls-"||$i,
      "format":if (contains($x[1],"avc1")) then
        "m3u8[h264+aac]"
      else
        "m3u8[aac]",
      "resolution":concat(
        extract($x[1],"RESOLUTION=([\dx]+)",1)[.],
        extract($x[1],"(?:FRAME-RATE=|GROUP-ID.+p)([\d\.]+)",1)[.] !
          concat("@",round-half-to-even(.,3),"fps")
      )[.],
      "bitrate":let $a:=extract($x[1],"audio.*?=(\d+)(?:-video.*?=(\d+))?",(1,2)) return
      concat(
        if ($a[1]) then
          join((round($a[2][.] div 1000),round($a[1] div 1000)),"|")
        else
          (
            round($br[.] div 1000),
            extract($x[1],"GROUP-ID=.+?-(\d+)",1)[.]
          ),
        "kbps"
      ),
      "url":resolve-uri(
        extract($x[1],"(?:.+URI=&quot;)?(.+m3u8(?:\?.+?$)?)",1,"m"),
        $m3u8Url
      )
    }
  )
};

declare function xivid:txt-to-date($txt as string) as string {
  let $a:={
        "januari":"01","februari":"02","maart":"03",
        "april":"04","mei":"05","juni":"06",
        "juli":"07","augustus":"08","september":"09",
        "oktober":"10","november":"11","december":"12"
      },
      $b:=extract($txt,"(\d+)\s+([a-z]+)\s+(\d{4})",(1 to 3))
  return
  join(
    (
      if ($b[1] lt 10) then "0"||$b[1] else $b[1],
      $a($b[2]),
      $b[3]
    ),
    "-"
  )
};

declare function xivid:bin-xor($a as integer,$b as integer) as integer {
  let $bin:=($a,$b) ! x:integer-to-base(.,2),
      $len:=max($bin ! string-length()),
      $val:=$bin ! concat(
        string-join((1 to $len - string-length()) ! 0),
        .
      ),
      $v1:=$val[1],
      $v2:=$val[2]
  return
  x:integer(
    string-join(
      for $x in 1 to $len return
      if (substring($v1,$x,1) eq substring($v2,$x,1)) then 0 else 1
    ),
    2
  )
};

declare function xivid:info($json as object()) as string* {
  let $a:={
        "name":"Naam:",
        "date":"Datum:",
        "duration":"Tijdsduur:",
        "start":"Begin:",
        "end":"Einde:",
        "expdate":"Gratis tot:",
        "formats":"Formaten:"
      },
      $b:=max(
        $a()[exists($json(.))] ! $a(.) ! string-length()
      ),
      $c:=[
        {
          "id":"id",
          "format":"formaat",
          "language":"taal",
          "resolution":"resolutie",
          "samplerate":"frequentie",
          "bitrate":"bitrate"
        },
        $json/(formats)()
      ],
      $d:=$c(1)() ! distinct-values(
        for $x in $c()[position() gt 1] return
        .[$x(.)]
      ),
      $e:=$d ! max($c()(.) ! string-length())
  return (
    $a()[exists($json(.))] ! concat(
      substring(
        $a(.)||string-join((1 to $b) ! " "),
        1,$b + 1
      ),
      if (.=$a()[last()]) then
        if (exists($c(2))) then
          join(
            $c() ! string-join(
              for $x at $i in $d return
              if (position() eq count($c()) and $i eq count($d)) then
                .($x)||" (best)"
              else
                substring(
                  .($x)||string-join((1 to $e[$i] + 2) ! " "),
                  1,$e[$i] + 2
                )
            ),
            "&#10;"||string-join((1 to $b + 1) ! " ")
          )
        else
          "-"
      else
        $json(.)
    ),
    $json[start]/(
      "",
      let $f:=(start,duration) ! (
        (time(.) - time("00:00:00")) div dayTimeDuration("PT1S")
      ) return
      concat(
        substring(
          "Download:"||string-join((1 to $b) ! " "),
          1,$b + 1
        ),
        "ffmpeg",
        ($f[1] - $f[1] mod 30) ! (if (. eq 0) then () else " -ss "||.),
        " -i <url>",
        ($f[1] mod 30) ! (if (. eq 0) then () else " -ss "||.),
        " -t ",
        $f[2],
        " [...]"
      )
    )
  )
};

declare function xivid:bbvms(
  $url as string?,
  $publ as string?,
  $title as string?
) as object()? {
  let $json:=json($url),
      $host:=$json/publicationData/resolve-uri(
        defaultMediaAssetPath,
        $json/protocol
      ),
      $orig:=json($json/clipData/s3Info)
  return
  $json/clipData/{|
    {
      "name":join(
        (
          if ($publ) then $publ else $json/publicationData/label,
          if ($title) then $title else .[title]/title
        ),
        ": "
      )
    },
    if (
      sourcetype="live" or
      contains((assets)()[ends-with(src,"m3u8")]/src,"/live/") or
      ends-with((assets)()[ends-with(src,"m3u8")]/src,"hls.m3u8")
    ) then {
      "date":format-date(current-date(),"[D01]-[M01]-[Y]")
    } else {
      "date":format-date(
        dateTime(publisheddate) + implicit-timezone(),
        "[D01]-[M01]-[Y]"
      ),
      "duration":.[length]/length * duration("PT1S") + time("00:00:00")
    },
    {
      "formats":[
        (subtitles)()/{
          "id":"sub-1",
          "format":"srt",
          "language":isocode,
          "label":languagename,
          "url":concat(
            $json/publicationData/baseurl,
            "/subtitle/",
            id,
            ".srt"
          )
        },
        xivid:m3u8-to-json(
          (assets)()[ends-with(src,"m3u8")][1]/resolve-uri(src,$host)
        ),
        for $x at $i in (assets)()[not(ends-with(src,"m3u8"))]
        order by $x/bandwidth
        count $i
        return
        $x/{
          "id":"pg-"||$i,
          "format":"mp4[h264+aac]",
          "resolution":.[width]/concat(width,"x",height),
          "bitrate":.[bandwidth]/concat(bandwidth,"kbps"),
          "url":resolve-uri(src,$host) ! (
            if (ends-with(.,"mp4")) then
              .
            else
              x:request({"method":"HEAD","url":.})/url
          )
        },
        {
          "id":"pg-"||count((assets)()[not(ends-with(src,"m3u8"))]) + 1,
          "format":concat(
            extract($orig/format/filename,".+\.(.+)",1),
            if ($orig/ContentType="video/mpeg2") then "[mpeg2+pcm]" else "[h264+aac]"
          ),
          "resolution":concat(originalWidth,"x",originalHeight),
          "bitrate":round(
            tokenize($orig/format/bit_rate)[1] * 1024
          )||"kbps",
          "url":$orig/format/filename
        }[url]
      ]
    }
  |}
};

(:~
 : --------------------------------
 : Extractors
 : --------------------------------
 :)

declare function xivid:npo($url as string) as object()? {
  let $prid:=extract($url,".+/([\w_]+)",1),
      $token:=x:request({
        "header":"X-Requested-With: XMLHttpRequest",
        "url":"https://www.npostart.nl/api/token"
      })/json/token,
      $token2:=x:request({
        "post":"_token="||$token,
        "url":"https://www.npostart.nl/player/"||$prid
      })/json,
      $info:=json(
        doc($token2/embedUrl)//script/extract(.,"var video =(.+);",1)[.]
      ),
      $stream:=json(
        concat(
          "https://start-player.npo.nl/video/",
          $prid,
          "/streams?profile=hls&amp;quality=npo&amp;tokenId=",
          $token2/token
        )
      )/stream[not(exists(protection))]/src
  return {|
    if (exists($info)) then $info/{
      "name":concat(
        franchiseTitle,
        if (contains(franchiseTitle,title)) then () else ": "||title
      ),
      "date":format-date(
        dateTime(broadcastDate) + implicit-timezone(),
        "[D01]-[M01]-[Y]"
      ),
      "duration":format-time(
        duration * duration("PT1S"),
        "[H01]:[m01]:[s01]"
      ),
      "start":if (startAt) then
        format-time(
          startAt * duration("PT1S"),
          "[H01]:[m01]:[s01]"
        )
      else
        (),
      "end":if (startAt) then
        format-time(
          (startAt + duration) * duration("PT1S"),
          "[H01]:[m01]:[s01]"
        )
      else
        ()
    } else
      doc("https://www.npostart.nl/"||$prid)/(
        let $info:=json(//script[@type="application/ld+json"]) return {
          "name"://npo-player-header/concat(
            @main-title,
            ": ",
            @share-title
          ),
          "date":format-date(
            dateTime($info/uploadDate),
            "[D01]-[M01]-[Y]"
          ),
          "duration":format-time(
            duration($info/duration),
            "[H01]:[m01]:[s01]"
          )
        }
      ),
    {
      "formats":[
        (
          if (not(exists($info/(subtitles)())) and $info/parentId) then
            json(
              doc(
                x:request({
                  "post":"_token="||$token,
                  "url":"https://www.npostart.nl/player/"||$info/parentId
                })/json/embedUrl
              )//script/extract(.,"var video =(.+);",1)[.]
            )
          else
            $info
        )/(subtitles)()/{
          "id":"sub-1",
          "format":"vtt",
          "language":language,
          "label":label,
          "url":src
        },
        xivid:m3u8-to-json($stream)
      ]
    }
  |}
};

declare function xivid:rtl($url as string) as object()? {
  json(
    concat(
      "http://www.rtl.nl/system/s4m/vfd/version=2/uuid=",
      if (contains($url,"rtlnieuws.nl")) then
        doc($url)//@data-uuid
      else
        extract($url,".+/(.+)",1),
      "/fmt=adaptive/"
    )
  )[meta/nr_of_videos_total gt 0]/{
    "name":concat(
      .//station,": ",
      abstracts/name,
      " - ",
      if (.//classname="uitzending") then episodes/name else .//title
    ),
    "date":format-date(
      (material)()/original_date * duration("PT1S") +
      implicit-timezone() + date("1970-01-01"),
      "[D01]-[M01]-[Y]"
    ),
    "duration":format-time(
      time((material)()/duration) + duration("PT0.5S"),
      "[H01]:[m01]:[s01]"
    ),
    "expdate":format-dateTime(
      (.//ddr_timeframes)()[model="AVOD"]/stop * duration("PT1S") +
      implicit-timezone() + dateTime("1970-01-01T00:00:00"),
      "[D01]-[M01]-[Y] [H01]:[m01]:[s01]"
    ),
    "formats":xivid:m3u8-to-json(.//videohost||.//videopath)
  }
};

declare function xivid:kijk($url as string) as object()? {
  let $json:=json(doc($url)//script[@type="application/json"])//pageProps return
  $json/video/{
    "name":concat(
      "Kijk: ",
      ($json/format,.)[1]/title,
      .[exists(seasonNumber)]/concat(
        " S",
        seasonNumber ! (if (. lt 10) then "0"||. else .),
        "E",
        tvSeasonEpisodeNumber ! (if (. lt 10) then "0"||. else .)
      )
    ),
    "date":format-date(
      epgDate div 1000 * duration("PT1S") + date("1970-01-01"),
      "[D01]-[M01]-[Y]"
    ),
    "duration":round(duration) * duration("PT1S") + time("00:00:00"),
    "formats":[
      for $x at $i in (.//sourceUrl)[ends-with(.,"vtt")]
      order by $x
      count $i
      return {
        "id":"sub-"||$i,
        "format":"vtt",
        "language":"nl",
        "label":if (contains($x,"OPE")) then
          "Doven en Slechthorenden"
        else
          "Nederlands",
        "url":$x
      },
      xivid:m3u8-to-json((.//sourceUrl)[ends-with(.,"m3u8")][last()])
    ]
  }
};

declare function xivid:tvblik($url as string) as object()? {
  let $host:=extract(
    doc($url)//(
      div[@id="embed-player"]/(@data-episode,a/@href),
      div[@class="video_thumb"]//@onclick,
      iframe[@class="sbsEmbed"]/@src
    ),
    "(npo|rtl|kijk).+(?:/|video=)([\w-]+)",
    (1,2)
  ) return
  if ($host[1]="npo") then
    xivid:npo("https://www.npostart.nl/"||$host[2])
  else if ($host[1]="rtl") then
    xivid:rtl("https://www.rtlxl.nl/video/"||$host[2])
  else
    xivid:kijk("https://kijk.nl/video/"||$host[2])
};

declare function xivid:regio($url as string) as object()? {
  let $src:=doc($url),
      $script:=resolve-uri(
        if ($url="https://www.omroepgelderland.nl/tv") then
          extract(
            unparsed-text("https://web.omroepgelderland.nl/epg/tv_vanavond/data/html/script.js"),
            "bbw_media_config_url = &apos;(.+)&apos;",1
          )
        else
          $src/(
            //@data-media-url,
            //article/iframe/@src,
            //div[
              starts-with(@class,"bluebillywig") or
              starts-with(@class,"customhtml") or
              @class="bbwLive-player"
            ]/script/@src,
            //div[starts-with(@class,"inlinemedia")]/iframe/@src,
            //div[starts-with(@class,"bluebillywig")]/iframe/@data-src,
            json(
              //script/extract(.,"playerInstance\.setup\((.+)\)",1,"s")[.]
            )//file,
            json(//script[@id="__NEXT_DATA__"])/props/pageProps/props/concat(
              "https://omroepbrabant.bbvms.com/p/default/",
              if (clip) then "c/"||clip else "q/sourceid_string:"||programId,
              ".json"
            ),
            //div[@class="bbw bbwVideo"]/concat(
              "https://limburg.bbvms.com/p/L1_video/c/",@data-id,".json"
            )
          ),
        $url
      ),
      $title:=$src/(
        //div[@class="media-details"]/h3,
        //div[@class="node-content-wrapper"]/header/normalize-space(h3),
        //h1[@class="title-KX" and not(contains(text(),"live"))],
        json(//script/substring-after(.,"var msTag = ")[.])/data/(content)()
      )
  return
  if (ends-with($script,"mp4")) then
    {
      "name":$src/concat(
        //meta[@name="publisher"]/@content,
        ": ",
        //form[@name="quick_menu2"]//option[@selected]
      ),
      "date":replace($script,".+?(\d+)/(\d+)/(\d+).+","$3-$2-$1"),
      "formats":[
        {
          "id":"pg-1",
          "format":"mp4[h264+aac]",
          "url":x:request({"method":"HEAD","url":$script})/url
        }
      ]
    }
  else
    xivid:bbvms(
      extract($script,".+\.")||"json",
      $src//meta[@name="publisher" or @property="og:site_name"]/@content,
      if ($title) then $title else "Livestream"
    )
};

declare function xivid:nhnieuws($url as string) as object()? {
  doc($url)/(
    if (//article) then
      json(
        //script/substring-after(.,"INITIAL_PROPS__ = ")[.]
      )/pageData/{
        "name":let $info:=(blocks)()[type=("video","headerVideo")]/video return
        if ($info/caption) then
          $info/concat(author,": ",caption)
        else
          concat(media//author,": ",title),
        "date":format-date(
          updated * duration("PT1S") + implicit-timezone() + date("1970-01-01"),
          "[D01]-[M01]-[Y]"
        ),
        "formats":xivid:m3u8-to-json(.//stream/url)
      }
    else {
      "name":substring-after(//title,"Media - ")||": Livestream",
      "date":format-date(current-date(),"[D01]-[M01]-[Y]"),
      "formats":xivid:m3u8-to-json(
        json(
          //script/substring-after(.,"INIT_DATA__ = ")[.]
        )/videoStream
      )
    }
  )
};

declare function xivid:ofl($url as string) as object()? {
  doc($url)/(
    let $info:=//div[@class="fn-jw-player fn-videoplayer"] return
    if ($info/@data-has-streams) then {
      "name":"Omroep Flevoland: Livestream",
      "date":format-date(current-date(),"[D01]-[M01]-[Y]"),
      "formats":xivid:m3u8-to-json($info/@data-file)
    } else {
      "name":concat(
        "Omroep Flevoland: ",
        if ($info/normalize-space(@data-title)) then
          $info/@data-title
        else
          normalize-space(//h2)
      ),
      "date":if (//meta[@itemprop="datePublished"]) then
        format-date(
          date(//meta[@itemprop="datePublished"]/@content),
          "[D01]-[M01]-[Y]"
        )
      else
        extract(//span[starts-with(@class,"t--red")],"[\d-]+"),
      "formats":[
        {
          "id":"pg-1",
          "format":"mp4[h264+aac]",
          "resolution":"960x540",
          "url":$info/@data-file
        }
      ]
    }
  )
};

declare function xivid:dumpert($url as string) {
  json(
    json(
      doc($url)//script/extract(.,"JSON\.parse\((.+)\)",1)[.]
    )
  )/items/item/item[exists((media)()[mediatype="VIDEO"])]/{
    "name":"Dumpert: "||title,
    "date":format-date(dateTime(date),"[D01]-[M01]-[Y]"),
    "duration":(media)()/duration * duration("PT1S") + time("00:00:00"),
    "formats":for $x at $i in ("mobile","tablet","720p","original")
    let $vid:=(.//variants)()[version=$x]/uri
    return {
      "id":"pg-"||$i,
      "format":"mp4[h264+aac]",
      "url":$vid
    }[url]
  }
};

declare function xivid:autojunk($url as string) as object()? {
  let $src:=doc($url),
      $info:=$src//div[@id="playerWrapper"]/script
  return {
    "name":"Autojunk: "||extract($info,"clipData.title=&quot;(.+)&quot;",1),
    "date":extract($src//span[@class="posted"],"([\d-]+)",1),
    "duration":format-time(
      extract($info,"clipData\[&quot;length&quot;\].+?(\d+)",1) * duration("PT1S"),
      "[H01]:[m01]:[s01]"
    ),
    "formats":[
      for $x at $i in json(
        replace(extract($info,"clipData.assets = (.+\]);",1,"s")," //.+","")
      )()[src]
      order by $x/bandwidth
      count $i
      return {
        "id":"pg-"||$i,
        "format":"mp4[h264+aac]",
        "resolution":concat($x/width,"x",$x/height),
        "bitrate":$x/bandwidth||"kbps",
        "url":$x/src
      }
    ]
  }
};

declare function xivid:telegraaf($url as string) as object()? {
  json(
    concat(
      "https://content.tmgvideo.nl/playlist/item=",
      json(
        doc($url)//script/extract(.,"APOLLO_STATE__=(.+);",1)[.]
      )/(.//videoId)[1],
      "/playlist.json"
    )
  )/(items)()/{
    "name":"Telegraaf: "||title,
    "date":format-date(
      date(tokenize(publishedstart)[1]),
      "[D01]-[M01]-[Y]"
    ),
    "duration":format-time(
      duration * duration("PT1S"),
      "[H01]:[m01]:[s01]"
    ),
    "expdate":publishedend ! format-dateTime(
      dateTime(replace(.,"\s","T")),
      "[D01]-[M01]-[Y] [H01]:[m01]:[s01]"
    ),
    "formats":[
      locations/reverse((progressive)())/{
        "id":"pg-"||position(),
        "format":"mp4[h264+aac]",
        "resolution":concat(width,"x",height),
        "url":.//src
      },
      xivid:m3u8-to-json(
        locations/(adaptive)()[type="application/x-mpegURL"]/extract(src,".+m3u8")
      )
    ]
  }
};

declare function xivid:ad($url as string) as object()? {
  let $id:=extract($url,"~p(\d+)",1),
      $json:=json(
        concat(
          "https://embed.mychannels.video/sdk/production/",
          if ($id) then
            $id
          else
            x:request({
              "headers":"Cookie: authId=8ac8ac9f-3782-4ba2-a449-9dc1fcdacbd5",
              "url":$url
            })/doc/(
              if (//*[@class="mc-embed"]) then
                //*[@class="mc-embed"]/extract(@src,"\d+")
              else
                //div[@data-mychannels-type="video"]/@data-mychannels-id
            ),
          "?options=FUTFU_default"
        )
      )
  return
  $json/{|
    {
      "name":concat(
        "AD: ",
        (shows)()/title,
        " - ",
        (productions)()/title
      )
    },
    (productions)()/{
      "date":format-date(
        date(tokenize(publicationDate)[1]),
        "[D01]-[M01]-[Y]"
      ),
      "duration":format-time(
        duration * duration("PT1S"),
        "[H01]:[m01]:[s01]"
      ),
      "formats":[
        for $x at $i in reverse((sources)()[type="video/mp4"]) return {
          "id":"pg-"||$i,
          "resolution":("640x360","1280x720")[$i],
          "format":"mp4[h264+aac]",
          "url":$x/src
        },
        xivid:m3u8-to-json((sources)(1)/src)
      ]
    }
  |}
};

declare function xivid:lc($url as string) as object()? {
  let $src:=x:request({
        "headers":"Cookie: ndc_consent={""permissions"":{""functional"":true}}",
        "url":$url
      })/doc,
      $id:=$src//div[@class="article-page__video-wrapper"]/div/substring-after(@id,"video-")
  return
  $src/xivid:bbvms(
    substring-before(
      json(//script/tokenize(.,",")[contains(.,$id)]),
      "html"
    )||"json",
    //meta[@property="og:site_name"]/@content,
    ()
  )
};

declare function xivid:youtube($url as string) as object()? {
  let $json:={|
    for $x in tokenize(
      unparsed-text("https://www.youtube.com/get_video_info?video_id="||extract($url,"\w+$")),
      "&amp;"
    )
    let $kv:=tokenize($x,"=") return {$kv[1]:uri-decode($kv[2])}
  |}/json(player_response) return
  $json//playerMicroformatRenderer/{|
    if (liveBroadcastDetails/isLiveNow) then {
      "name":title/simpleText,
      "date":format-date(current-date(),"[D01]-[M01]-[Y]"),
      "formats":xivid:m3u8-to-json($json/streamingData/hlsManifestUrl)
    } else {
      "name":title/simpleText,
      "date":format-date(date(uploadDate),"[D01]-[M01]-[Y]"),
      "duration":format-time(lengthSeconds * duration("PT1S"),"[H01]:[m01]:[s01]"),
      "formats":[
        ($json//captionTracks)()[languageCode=("nl","en")]/{
          "id":"sub-"||position(),
          "format":"ttml",
          "language":languageCode,
          "label":name/simpleText,
          "url":baseUrl
        },
        for $x at $i in $json/streamingData/(formats)()[url]
        order by $x/width
        count $i
        return {
          "id":"pg-"||$i,
          "format":let $mt:=tokenize($x/mimeType,";"),
              $c:=tokenize(
                extract($mt[2],"&quot;(.+)&quot;",1),
                ", "
              ) ! tokenize(.,"\.")[1]
          return
          concat(
            substring-after($mt[1],"/"),
            "[",
            if ($c[1]="avc1") then "h264" else $c[1],
            "+",
            if ($c[2]="mp4a") then "aac" else $c[2],
            "]"
          ),
          "resolution":concat($x/width,"x",$x/height,"@",$x/fps,"fps"),
          "bitrate":concat(round($x/bitrate div 1000),"kbps"),
          "url":$x/url
        },
        {
          "id":"dash-0",
          "format":"mpd[manifest]",
          "url":$json/streamingData/dashManifestUrl
        }[url]
      ]
    }
  |}
};

declare function xivid:dailymotion($url as string) as object()? {
  json(replace($url,"video","player/metadata/video"))/{
    "name":"Dailymotion: "||title,
    "date":format-date(
      created_time * duration("PT1S") +
      implicit-timezone() + date("1970-01-01"),
      "[D01]-[M01]-[Y]"
    ),
    "duration":format-time(
      duration * duration("PT1S"),
      "[H01]:[m01]:[s01]"
    ),
    "formats":xivid:m3u8-to-json(qualities//url)
  }
};

declare function xivid:mixcloud($url as string) as object()? {
  let $key:=x:cps("IFYOUWANTTHEARTISTSTOGETPAIDDONOTDOWNLOADFROMMIXCLOUD"),
      $decrypt:=function($arg as string) as string {
        string-join(
          x:cps(
            for $x at $i in x:cps(binary-to-string(base64Binary($arg))) return
            xivid:bin-xor($x,$key[($i - 1) mod count($key) + 1])
          )
        )
      },
      $csrf:=x:request(
        {"method":"HEAD","url":$url}
      )/substring-before(substring-after(headers[contains(.,"csrftoken")],"="),";"),
      $us:=tokenize(substring-after($url,"mixcloud.com/"),"/")
  return
  x:request({
    "headers":(
      "Content-Type: application/json",
      "Referer: "||$url,
      "X-CSRFToken: "||$csrf,
      "Cookie: csrftoken="||$csrf
    ),
    "post":concat(
      "{""query"":""{cloudcastLookup(lookup:{username:\""",
      $us[1],
      "\"",slug:\""",
      $us[2],
      "\""}){name,owner{displayName,url,username},publishDate,audioLength,streamInfo{hlsUrl,url}}}""}"
    ),
    "url":"https://www.mixcloud.com/graphql"
  })/json//cloudcastLookup/{
    "name":concat(owner/displayName," - ",name),
    "date":format-date(dateTime(publishDate),"[D01]-[M01]-[Y]"),
    "duration":format-time(audioLength * duration("PT1S"),"[H01]:[m01]:[s01]"),
    "formats":[
      {
        "id":"pg-1",
        "format":"m4a[aac]",
        "url":$decrypt(streamInfo/url)
      },
      xivid:m3u8-to-json(
        $decrypt(streamInfo/hlsUrl)
      )
    ]
  }
};

declare function xivid:soundcloud($url as string) as object()? {
  let $src:=doc($url),
      $cid:=substring(
        substring-after(
          unparsed-text($src//script[@crossorigin][last()]/@src),
          "client_id:"
        ),
        2,32
      ),
      $json:=json($src//script/extract(.,"(\[\{.+)\)",1)[.])()[last()]/(data)(),
      $fmts:=($json//transcodings)()
  return
  $json/{
    "name":concat(user/(full_name,username)[.][1]," - ",title),
    "date":format-date(dateTime(created_at),"[D01]-[M01]-[Y]"),
    "duration":format-time(
      round(duration div 1000) * duration("PT1S"),
      "[H01]:[m01]:[s01]"
    ),
    "formats":[
      $fmts[format/protocol="progressive"]/(
        let $url:=json(concat(url,"?client_id=",$cid))/url return {
          "id":"pg-1",
          "format":substring-before(preset,"_"),
          "bitrate":extract($url,"\.(\d+)\.",1)||"kbps",
          "url":$url
        }
      ),
      for $x at $i in $fmts[format/protocol="hls"]
      order by $x/preset descending
      count $i
      let $url:=json(concat($x/url,"?client_id=",$cid))/url
      return {
        "id":"hls-"||$i,
        "format":concat("m3u8[",substring-before($x/preset,"_"),"]"),
        "bitrate":extract($url,"\.(\d+)\.",1)||"kbps",
        "url":$url
      }
    ]
  }
};

declare function xivid:pornhub($url as string) as object()? {
  let $src:=doc($url),
      $info:=json($src//script[@type="application/ld+json"]),
      $fmts:=for $x in $src//div[@id="player"]/tokenize(
        replace(script,"&quot; \+ &quot;|&quot;",""),
        "flashvars.+?;"
      )[contains(.,"var media_")]
      order by extract($x,"media_(\d+)",1) descending
      return
      string-join(
        extract($x,"\*/(\w+)",1,"*") ! substring-before(substring-after($x,.||"="),";")
      )
  return {
    "name":"Pornhub: "||$info/name,
    "date":format-date(
      dateTime($info/uploadDate) + implicit-timezone(),
      "[D01]-[M01]-[Y]"
    ),
    "duration":format-time(duration($info/duration),"[H01]:[m01]:[s01]"),
    "formats":[
      for $x at $i in $fmts[not(contains(.,"m3u8"))]
      count $i
      return {
        "id":"pg-"||$i,
        "format":"mp4[h264+aac]",
        "resolution":("426x240","854x480","1280x720","1920x1080")[$i],
        "url":$x
      },
      xivid:m3u8-to-json($fmts[1])
    ]
  }
};
