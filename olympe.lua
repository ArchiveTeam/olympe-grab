dofile("urlcode.lua")
dofile("table_show.lua")

local url_count = 0
local tries = 0
local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')

local downloaded = {}
local addedtolist = {}
local seedurls = {}

for seedurl in io.open("seedurls", "r"):lines() do
  seedurls[seedurl] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if (downloaded[url] ~= true and addedtolist[url] ~= true) and (seedurls[string.match(url, "^https?://([^/]+)")] == true or html == 0) then
    addedtolist[url] = true
    return true
  else
    return false
  end
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local url = string.gsub(string.match(urla, "^([^#]+)"),"^https?://", "http://")
    if (downloaded[url] ~= true and addedtolist[url] ~= true) and seedurls[string.match(url, "^https?://([^/]+)")] == true then
      if string.match(url, "&amp;") then
        table.insert(urls, { url=string.gsub(url, "&amp;", "&") })
        addedtolist[url] = true
        addedtolist[string.gsub(url, "&amp;", "&")] = true
      else
        table.insert(urls, { url=url })
        addedtolist[url] = true
      end
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^//") then
      check("http:"..newurl)
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)")..newurl)
    elseif not (string.match(newurl, "^https?://") or string.match(newurl, "^/") or string.match(newurl, "^[jJ]ava[sS]cript:") or string.match(newurl, "^[mM]ail[tT]o:") or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)")..newurl)
    end
  end
  
  if seedurls[string.match(url, "^https?://([^/]+)")] == true and not (string.match(url, "%.[mM][pP]4$") or string.match(url, "%.[mM][pP]3$") or string.match(url, "%.[jJ][pP][gG]$") or string.match(url, "%.[gG][iI][fF]$") or string.match(url, "%.[pP][nN][gG]$") or string.match(url, "%.[sS][vV][gG]$") or string.match(url, "%.[iI][cC][oO]$") or string.match(url, "%.[aA][vV][iI]$") or string.match(url, "%.[fF][lL][vV]$") or string.match(url, "%.[pP][dD][fF]$") or string.match(url, "%.[rR][mM]$") or string.match(url, "%.[rR][aA]$") or string.match(url, "%.[wW][mM][vV]$") or string.match(url, "%.[jJ][pP][eE][gG]$") or string.match(url, "%.[sS][wW][fF]$")) then
    html = read_file(file)
    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">([^<]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "%(([^%)]+)%)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, 'href="([^"]+)"') do
      checknewshorturl(newurl)
    end
  end

  return urls
end
  

wget.callbacks.httploop_result = function(url, err, http_stat)
  -- NEW for 2014: Slightly more verbose messages because people keep
  -- complaining that it's not moving or not working
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  local function check_loop(part_)
    for part in part_ do
      part = string.gsub(part, '(['..("%^$().[]*+-?"):gsub("(.)", "%%%1")..'])', "%%%1")
      if string.find(url["url"], "/"..part.."/"..part.."/"..part.."/") or string.find(url["url"], "&"..part.."&"..part.."&"..part.."&") or string.find(url["url"], "%%"..part.."%%"..part.."%%"..part.."%%") then
        return wget.actions.EXIT
      end
    end
  end

  if downloaded[url["url"]] == true and status_code >= 200 and status_code < 400 then
    return wget.actions.EXIT
  end

  if (status_code >= 200 and status_code < 400) then
    downloaded[url["url"]] = true
  end

  check_loop(string.gmatch(url["url"], "([^/]*)"))
  check_loop(string.gmatch(url["url"], "([^/]+/[^/]*)"))
  check_loop(string.gmatch(url["url"], "([^%%]*)"))
  check_loop(string.gmatch(url["url"], "([^%%]+%%[^%%]*)"))
  check_loop(string.gmatch(url["url"], "([^&]*)"))
  check_loop(string.gmatch(url["url"], "([^&]+&[^&]*)"))
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404) or
    status_code == 0 then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 8")
    tries = tries + 1
    if tries >= 10 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if seedurls[string.match(url["url"], "^https?://([^/]+)")] == true then
        return wget.actions.EXIT
      else
        return wget.actions.EXIT
      end
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end