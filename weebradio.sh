#!/bin/bash

readonly hibiki_radio="https://hibiki-radio.jp/"
readonly asobi_store="https://asobistore.jp/"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

OUTPUT="$PWD" #default value
episodeDetail=""
episodeCover=""

function requirements {
  local deps="grep curl jq ffmpeg sqlite3 xmllint youtube-dl"
  local ng=0

  for dep in $deps; do
    type $dep >/dev/null 2>&1 || {
      echo -e "${RED}ERROR: ${CYAN}$dep${NC} not be installed.${NC}" >&2
      ng=1
    }
  done
  return $ng
}

function usage {
  cat << EOF
weebradio: download and manage audio streams from different japanese internet radio services (HiBiKi Radio and Asobi store)

Usage:
  weebradio [command] --source <asobi|hibiki> --url <url> --id <id> --output <path> --database <filepath>

Commands:
  download: download latest episode.
    For Asobi Store radio shows: This can be used --url "https://asobistore.jp/special/Detail?seq=<Sequence ID for episode>" 
  init: initialize database file


Parameters:
  source:
    asobi: Asobi Store
    hibiki: Hibiki Radio

  url:
    HiBiKi Radio or Asobi Store non-premium radio show URL

    e.g.: 
      Hibiki Radio: https://hibiki-radio.jp/description/Roselia
      Asobi Store: https://asobistore.jp/special/List?tag_seq%5B%5D=1

  id:
    HiBiKi Radio or Asobi Store show id
    e.g.: 
      Hibiki Radio: Roselia
      Asobi Store: shinyradio
  output:
    Folder path to store audio (Only used in download, update and updateAll). Default value is \$PWD
  database:
    File path to database (only used in init, add, update and updateAll). Default value is \$output\\radioentries.db
EOF
}


# isDatabaseFileExist "Database"
function isDatabaseFileExist {
  return $(test -f "$1") # TO-DO: also check if database tables are correct
}

# isValidId
function isValidId {
  return $([[ "$1" =~ ^[^\/]+$ ]])
}

# isValidUrl "URL"
function isValidUrl {
  return $([[ "$1" =~ (hibiki-radio.jp)|(asobistore.jp) ]])
}

# getSearchTerm "asobiURL"
function getSearchTermAsobi {
  local asobiUrl="$1"
  if [[ "$asobiUrl" =~ (List) ]]; then
    local episodeUrl="${asobi_store}$(curl -s "$asobiUrl" | xmllint --html --xpath "string(//ul[@class='list-main-product']/li/*/div[p='視聴制限なし']/../@href)" - 2>/dev/null)"
  else
    local episodeUrl="$asobiUrl"
  fi
  echo "$(curl -s "$episodeUrl"| xmllint --html --xpath "//ul[@class='list-dcm']/li[2]/text()" - 2>/dev/null)"
}

function idGet {
  case $SOURCE in
    hibiki)
      local accessId=$(echo "$URL" | grep -oP '(?<=description/)[^ ]*(?=/detail)')
      [ "$accessId" = "" ] && {
        echo -e "${RED}Can't find ID.${NC}"
        exit 1
      }
      ID="$accessId"
      ;;
    asobi)
      local idSearch="$(getSearchTermAsobi "$URL")"
      local result="$(sqlite3 "${DATABASE}" "SELECT DISTINCT ShowName FROM asobiid WHERE SearchTerm=\"${idSearch}\"")"
      if [[ "$result" != "" ]]; then
        echo "$result"
        ID="$idSearch"
      else
        echo -e "${RED}Can't find ID.${NC}"
        exit 1
      fi
      ;;
  esac
}

# getAPIURL
function getApiUrlHibiki {
  URL="${hibiki_radio}description/${ID}"
  local baseUrl=$(
  curl -s "$URL" \
    | grep -oP '(?<=src=")[^ ]*app[^ ]*\.js' \
    | {
      read jsPath
   
      js=$(curl -s ${hibiki_radio}${jsPath})
   
      apiHost=$(echo "$js" | grep -oP '(?<=constant\("apiHost",")[^"]*')
      apiBase=$(echo "$js" | grep -oP '(?<=apiBase=")[^"]*')
      echo "${apiHost}${apiBase}"
    }
  )

  [ "$baseUrl" = "" ] && {
    echo -e "${RED}API URL not found.${NC}"
    exit 1
  }
  apiUrl="${baseUrl}programs/${ID}"
}

# getStreamHibiki
function getStreamHibiki {
  getApiUrlHibiki
  episodeDetail=$(curl -s "$apiUrl" -H 'X-Requested-With: XMLHttpRequest')

  local result=$(
    echo $episodeDetail \
    | jq .episode.video.id \
    | sed -E 's/\r$//' \
    | xargs -I{} curl -s 'https://vcms-api.hibiki-radio.jp/api/v1/videos/play_check?video_id={}' \
                 -H 'X-Requested-With: XMLHttpRequest' \
    | jq .playlist_url
  )
  streamURL="$result"
}

# getStreamAsobi "sequenceUrl"
function getStreamAsobi {
  local sequenceUrl="$1"
  episodeDetail="$(curl -s "$sequenceUrl")"
  local playerUrl="$(echo "$episodeDetail" \
    | xmllint --html --xpath "string(//div[@class='wrap-movie']/iframe/@src)" - 2>/dev/null)"
  [[ "$playerUrl" == "" ]] && {
    echo -e "${RED}Can't get playerUrl.${NC}"
    exit 1
  }
  streamURL="$(curl -s "https:${playerUrl}" | xmllint --html --xpath "string(//source/@src)" - 2>/dev/null)"
  episodeCover="https:$(curl -s "https:${playerUrl}" | xmllint --html --xpath "string(//video/@poster)" - 2>/dev/null)"
  [[ "$streamURL" == "" ]] && {
    echo -e "${RED}Can't get streamURL.${NC}"
    exit 1
  }
}

function getUrlFromIdAsobi {
  local result="$(sqlite3 "${DATABASE}" "SELECT url FROM asobiid WHERE ShowName=\"${ID}\";")"
  [ "$result" == "" ] && {
    echo -e "${RED}URL not found.${NC}"
    exit 1
  } 
  URL="$result"
}

# getEpisodeCover "pictureName" "outputPath"
function getEpisodeCover {
  local pictureName="$1"
  local outputPath="$2"
  curl -s "$episodeCover" --output "${outputPath}/${pictureName}.jpg"
  episodeCover="${outputPath}/${pictureName}.jpg"
}

# prettify "text"
function prettify {
  readarray -t temp <<<"$1"
  local formattedText=""
  local isCreditPart=0
  for line in "${!temp[@]}"; do
    if [[ "${temp[$line]}" =~ ^(https:) ]]; then
      formattedText+="${temp[$line]}"$'\n'
      formattedText+=$'\n'
    elif [[ "${temp[$line]}" =~ (（.*）)$ ]]; then
      formattedText+="${temp[$line]}"$'\n'
      isCreditPart=1
    else
      [ $isCreditPart -eq 1 ] && {
        formattedText+=$'\n'
        isCreditPart=0
      }
      formattedText+="${temp[$line]}"$'\n'
    fi
  done
  formattedText="$(echo "$formattedText" | sed '$d')"
  echo "$formattedText"
}

# downloadInfoAsobi "SequenceUrl" "outputBase"
function downloadInfoAsobi {
  local sequenceUrl="$1"
  local outputBase="$2"

  local episodeTitle="$(echo "$episodeDetail" | xmllint --html --xpath "//div[@class='wrap-main-info']/h1/text()" - 2>/dev/null)"
  local episodeDate="$(echo "$episodeDetail" | xmllint --html --xpath "//div[@class='wrap-main-info']/ul/li/time[1]/text()" - 2>/dev/null)"
  echo -e"${GREEN}Downloading information about episode: ${CYAN}${episodeTitle}${NC}"
  if [ ! -d "${outputBase}/${episodeTitle}" ]; then
    mkdir "${outputBase}/${episodeTitle}"
  fi
  local outputPath="${outputBase}/${episodeTitle}"
  getEpisodeCover "cover" "$outputPath"

  local episodeDescription="Published: ${episodeDate}"$'\n\n'
  local temp="$(curl -s "$sequenceUrl" | xmllint --html --xpath "//div[@class='wrap-main-info']/p/text() | //div[@class='wrap-main-info']/p/a/@href" - 2>/dev/null | sed 's/&#13;//g' | grep -oP '((?<=href=")[^ "]*(?="))|(^((?!href)[\s\S])*$)')"
  episodeDescription+="$(prettify "$temp")"
  echo "$episodeDescription" >> "${outputPath}/description.txt"
}

# downloadInfoHibiki "outputBase"
function downloadInfoHibiki {
  local outputBase="$1"

  local episodeTitle="$(echo "$episodeDetail" | jq .episode.name \
      | sed -e 's/^"//' -e 's/"$//')"
  local episodeDate="$(echo ${episodeDetail} | jq .episode.updated_at)"
  echo -e "${GREEN}Downloading information about episode: ${CYAN}${episodeTitle}${NC}"
  if [ ! -d "${outputBase}" ]; then
    mkdir "${outputBase}"
  fi
  if [ ! -d "${outputBase}/${episodeTitle}" ]; then
    mkdir "${outputBase}/${episodeTitle}"
  fi
  local outputPath="${outputBase}/${episodeTitle}"
  local results="$(echo "$episodeDetail" | jq '[.episode.episode_parts[]| {image: .pc_image_url, description: .description}]')"
  local arraySize="$(echo "$results" | jq '. | length')"
  local temp=""
  local parsedResult="Published: ${episodeDate}"$'\n\n'
  local imageCount=0
  local imageName=""
  for ((i=0;i<arraySize; i++)); do
    temp="$(echo "$results" | jq -r .["$i"].image)"
    [ "$temp" != "" ] && {
      ((imageCount++))
      imageName="$(printf "%03d\n" $imageCount).jpg"
      curl -s "$temp" -o "${outputPath}/${imageName}"
      parsedResult+="![${imageName}]:(./$imageName)"$'\n'
    }
    temp="$(echo "$results" | jq -r .["$i"].description)"
    [ "$temp" != "" ] && {
      parsedResult+="$temp"
    }
  done
  echo "$parsedResult" >> "${outputPath}/description.txt"
}

# parseAsobiStore "listURl" "mode"
function parseAsobiStore {
  local listUrl="$1"
  local mode="$2"

  local results=""
  if [[ "$listUrl" =~ (&page=) ]]; then
    results="$(curl -s "$listUrl" | xmllint --html --xpath "//li[starts-with(@class,'category1')]/a/@href | //li[starts-with(@class,'category1')]/a/div[@class='wrap-low']/p[@class='txt-member']/text()" - 2>/dev/null)"
  else
    local totalPages="$(curl -s "$listUrl" | xmllint --html --xpath "//li[@class='next']/preceding-sibling::li[1]/a/text()" - 2>/dev/null)"
    for ((page=1; page<=$totalPages; page++)); do
      results+="$(curl -s "${listUrl}&page=${page}" | xmllint --html --xpath "//li[starts-with(@class,'category1')]/a/@href | //li[starts-with(@class,'category1')]/a/div[@class='wrap-low']/p[@class='txt-member']/text()" - 2>/dev/null)"$'\n'
    done
  fi

  [ "$results" = "" ] && {
    echo -e "${RED}Can't parse Asobi Store.${NC}"
    exit 1
  }

  local i=0
  local temp=""
  local parsedResults=""
  for result in $results; do
    if [ $i -eq 0 ]; then
      temp="${asobi_store}$(echo "$result" | grep -oP '(?<=href="/)[^"]*')"$'\n'
      ((i++))
    elif [[ "$result" == "プレミアム会員限定" ]] && [[ "$mode" == "premium" ]]; then
      parsedResults+="$temp"
      i=0
    elif [[ "$result" == "視聴制限なし" ]] && [[ "$mode" == "free" ]]; then
      parsedResults+="$temp"
      i=0
    else
      i=0
    fi
  done
  parsedResults="$(echo "$parsedResults" | sed '$d')"
  echo "$parsedResults"
}

# add "asobiListUrl<optional>"
function add {
  [ "$1" = "" ] && {
    local asobiListUrl="$URL"
  } || {
    local asobiListUrl="$1"
  }

  [ "$ID" = "" ] && {
    idGet
  }
  local result=""
  case $SOURCE in
    hibiki)
      result="$(sqlite3 "$DATABASE" "SELECT * FROM hibiki WHERE ShowName=\"${ID}\"")"
      if [[ "$result" == "" ]]; then
        sqlite3 "$DATABASE" "INSERT INTO hibiki VALUES (\"${ID}\",\"\",\"\")"
      else
        echo -e "${RED}${ID} is already in database.${NC}"
      fi
      ;;
    asobi)
      result="$(sqlite3 "$DATABASE" "SELECT * FROM asobiid WHERE ShowName=\"${ID}\"")"
      if [[ "$result" == "" ]]; then
        [[ "$asobiListUrl" =~ ^(https://asobistore.jp/special/Detail)[^/]*$ ]] && {
          echo -e "${RED}Only Asobi store lists are allowed.${NC}"
          exit 1
        }
        local searchTerm="$(getSearchTermAsobi "$asobiListUrl")"
        sqlite3 "$DATABASE" "INSERT INTO asobiid VALUES (\"${ID}\",\"${asobiListUrl}\",\"${searchTerm}\")"
        echo -e "${GREEN}Show successfully added.${NC}"
      else
        echo -e "${RED}${ID} is already in database.${NC}"
      fi
      ;;
  esac
}

# download "StreamUrl(optional)" "recursion"
function download {
  [ "$ID" = "" ] && {
    idGet
  }
  
  local iter
  [[ "$2" = "" ]] && {
    iter=0
  } || {
    iter=$2
  }

  if [ ! -d "${OUTPUT}/${ID}" ]; then
    mkdir "${OUTPUT}/${ID}"
    mkdir "${OUTPUT}/${ID}/info"
  fi
  local folderPath="${OUTPUT}/${ID}"

  case $SOURCE in
    hibiki)
      [ "$1"="" ] && {
        getStreamHibiki
      } || {
        streamURL="$1"
      }
      local episodeTitle="$(echo "$episodeDetail" | jq .episode.name \
        | sed -e 's/^"//' -e 's/"$//')"
      echo "$streamURL" | xargs -I{} youtube-dl {} --hls-prefer-native --prefer-ffmpeg --postprocessor-args " -vn-c:a copy -bsf:a aac_adtstoasc" -o "${folderPath}/${episodeTitle}.aac"
      if [ ! -f "${folderPath}/${episodeTitle}.aac" ]; then
        if (( $iter > 3 )); then
            echo -e "${RED}Download failed. Aborting...${NC}"
            return 1
        fi
        echo -e "${RED}Download failed. Retrying...${NC}"
        ((iter++))
        download "$streamURL" "$iter"
      fi
      downloadInfoHibiki "${folderPath}/info"
      ;;
    asobi)
      if [[ "$1" == "" ]]; then
        if [[ "$URL" =~ (Detail)  ]]; then
          getStreamAsobi "$URL"
          local episodeTitle="$(echo "$episodeDetail" | xmllint --html --xpath "//div[@class='wrap-main-info']/h1/text()" - 2>/dev/null)"
          echo "$streamURL" | xargs -I{} youtube-dl {} --hls-prefer-native --prefer-ffmpeg --postprocessor-args "-vn -c:a copy -bsf:a aac_adtstoasc" -o "${folderPath}/${episodeTitle}.aac"
          if [ ! -f "${folderPath}/${episodeTitle}.aac" ]; then
            if (( $iter > 3 )); then
              echo -e "${RED}Download failed. Aborting...${NC}"
              return 1
            fi
            echo -e "${RED}Download failed. Retrying...${NC}"
            ((iter++))
            download "$streamURL" "$iter"
          fi
          downloadInfoAsobi "$URL" "${folderPath}/info"
        else
          local sequenceUrls="$(parseAsobiStore "$URL" "free")"
          for sequenceUrl in $sequenceUrls; do
            download "$sequenceUrl" #recurse
          done
        fi
      else
        streamURL="$1"
        local episodeTitle="$(echo "$episodeDetail" | xmllint --html --xpath "//div[@class='wrap-main-info']/h1/text()" - 2>/dev/null)"
        echo "$streamURL" | xargs -I{} youtube-dl {} --hls-prefer-native --prefer-ffmpeg --postprocessor-args "-vn -c:a copy -bsf:a aac_adtstoasc" -o "${folderPath}/${episodeTitle}.aac"
        if [ ! -f "${folderPath}/${episodeTitle}.aac" ]; then
            if (( $iter > 3 )); then
              echo -e "${RED}Download failed. Aborting...${NC}"
              return 1
            fi
          echo -e "${RED}Download failed. Retrying...${NC}"
          ((iter++))
          download "$streamURL" "$iter"
        fi
        downloadInfoAsobi "$URL" "${OUTPUT}/${ID}/info"
      fi
      ;;
    *)
      echo "Not yet implemented"
    ;;
  esac
}

# update "asobiDetail"
function update {
  [ "$ID" = "" ] && {
    idGet
  }
  [ "$1" != "" ] && {
    URL="$1"
  }

  case $SOURCE in 
    hibiki)
      getStreamHibiki
      local episodeTitle="$(echo ${episodeDetail} | jq .episode.name)"
      local episodeDate="$(echo ${episodeDetail} | jq .episode.updated_at)"

      # Find if latest show is already downloaded
      local result="$(sqlite3 "${DATABASE}" "SELECT * FROM hibiki WHERE ShowName=\"${ID}\" AND EpisodeTitle=${episodeTitle} AND Date=${episodeDate};")"
      if [ -n "${result}" ]; then
        echo -e "${CYAN}${ID}: ${GREEN}Latest episode already downloaded.${NC}"
      else
        echo -e "${CYAN}${ID}: ${GREEN}Downloading latest episode.${NC}"
        download "$streamURL"
        sqlite3 "${DATABASE}" "INSERT INTO hibiki VALUES (\"${ID}\", ${episodeTitle}, ${episodeDate});"
        echo -e "${CYAN}${ID}: ${GREEN}Update successful.${NC}"
      fi
    ;;
    asobi)
      if [ "$URL" = "" ]; then
        getUrlFromIdAsobi
      fi
      if [[ "$URL" =~ (Detail)  ]]; then
          getStreamAsobi "$URL"
          local episodeTitle="$(echo "$episodeDetail" | xmllint --html --xpath "//div[@class='wrap-main-info']/h1/text()" - 2>/dev/null)"
          local episodeDate="$(echo "$episodeDetail" | xmllint --html --xpath "//div[@class='wrap-main-info']/ul/li/time[1]/text()" - 2>/dev/null)"
          local result="$(sqlite3 "${DATABASE}" "SELECT * FROM asobi WHERE ShowName=\"${ID}\" AND EpisodeTitle=\"${episodeTitle}\" AND Date=\"${episodeDate}\";")"
          if [ -n "${result}" ]; then
            echo -e "${CYAN}${ID}: ${GREEN}Latest episode already downloaded.${NC}"
          else
            echo -e "${CYAN}${ID}: ${GREEN}Downloading latest episode.${NC}"
            download "$streamURL"
            sqlite3 "${DATABASE}" "INSERT INTO asobi VALUES (\"${ID}\", \"${episodeTitle}\", \"${episodeDate}\", 0);"
            echo -e "${CYAN}${ID}: ${GREEN}Update successful.${NC}"
          fi
        else
          local result="$(sqlite3 "$DATABASE" "SELECT * FROM asobiid WHERE ShowName=\"${ID}\"")"
          [ "$result" = "" ] && {
            add "$URL"
          }
          local sequenceUrls="$(parseAsobiStore "$URL" "free")"
          for sequenceUrl in $sequenceUrls; do
            update "$sequenceUrl"
          done
        fi
      ;;
    *)
      echo "Not yet implemented"
  esac
}

function updateAll {
  echo -e "${GREEN}Updating HiBiKi radio Shows.${NC}"
  local hibikiShows="$(sqlite3 "${DATABASE}" "SELECT DISTINCT ShowName FROM hibiki")"
  for hibikiShow in $hibikiShows; do
    ID="$hibikiShow"
    URL=""
    SOURCE="hibiki"
    update
  done
  echo -e "${GREEN}Updating Asobi Store radio shows.${NC}"
  local asobiShows="$(sqlite3 "${DATABASE}" "SELECT DISTINCT ShowName FROM asobiid")"
  for asobiShow in $asobiShows; do
    ID="$asobiShow"
    URL=""
    SOURCE="asobi"
    update
  done
  echo -e "${GREEN}Done updating all.${NC}"
}

function init {
  echo -e "${GREEN}Creating database file.${NC}"
  sqlite3 "$DATABASE" "CREATE TABLE hibiki (
    ShowName TEXT,
    EpisodeTitle TEXT,
    Date TEXT);"
  sqlite3 "$DATABASE" "CREATE TABLE asobi (
    ShowName TEXT,
    EpisodeTitle TEXT,
    Date TEXT
    isPremium BOOL);"
  sqlite3 "$DATABASE" "CREATE TABLE asobiid (
    ShowName TEXT,
    URL TEXT,
    SearchTerm TEXT);"
    echo -e "${GREEN}Done.${NC}"
}

while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
    init)
      ;&
    add)
      ;&
    remove)
      ;&
    download)
      ;&
    update)
      ;&
    updateAll)
      COMMAND="$1"
      shift
      ;;
    -h|--help|help)
      usage
      exit 0
      ;;
    -s|--source)
      SOURCE="$2"
      if [[ "$SOURCE" != "asobi" ]] && [[ "$SOURCE" != "hibiki" ]]; then
        echo -e "${RED}Not valid options for source parameter${NC}"
        exit 1
      fi
      shift
      shift
      ;;
    -u|--url)
      URL="$2"
      ! isValidUrl "$URL" && {
        echo -e "${RED}Not valid or supported URL.${NC}"
        exit 1
      }
      shift
      shift
      ;;
    -i|--id)
      ID="$2"
      ! isValidId "$ID" && {
        echo -e "${RED}Not valid ID.${NC}"
        exit 1
      }
      shift
      shift
      ;;
    -o|--output)
      [[ "$2" =~ ^[^~/] ]] && {
        OUTPUT="${PWD}/${2%/}"
      } || {
        OUTPUT="$2"
      }
      shift
      shift
      ;;
    -d|--database)
      [[ "$2" =~ ^[^~/] ]] && {
        DATABASE="${PWD}/${2%/}"
      } || {
        DATABASE="$2"
      }
      shift
      shift
      ;;
    *)    
      echo -e "${RED}${key} is invalid.${NC}"
      shift
      ;;
  esac
done


case $COMMAND in
  download)
    echo "$ID"
    if [[ -z "$SOURCE" ]]; then
      echo "Source parameter is empty"
      exit 1
    elif [[ "$URL" == "" ]] && [[ "$ID" == "" ]]; then
      echo "URL and ID parameter is empty"
      exit 1
    else
      download
    fi
    ;;
  update)
    if [[ -z "$DATABASE" ]]; then
      DATABASE="${OUTPUT}/radioentries.db"
    fi
    isDatabaseFileExist "$DATABASE" && {
      update
    } || {
      echo "No database found"
      exit 1
    }
    ;;
  updateAll)
    if [[ -z "$DATABASE" ]]; then
      DATABASE="${OUTPUT}/radioentries.db"
    fi
    echo "DATABASE = ${DATABASE}"
    isDatabaseFileExist "$DATABASE" && {
      updateAll
    } || {
      echo "No database found"
      exit 1
    }
    ;;
  add)
    if [[ -z "$DATABASE" ]]; then
      DATABASE="${OUTPUT}/radioentries.db"
    fi
    if [[ "$URL" == "" ]] && [[ "$ID" == "" ]]; then
      echo "URL and ID parameter is empty"
      exit 1
    fi
    isDatabaseFileExist "$DATABASE" && {
      add
    } || {
      echo "No database found"
      exit 1
    }
    ;;
  init)
    if [[ -z "$DATABASE" ]]; then
      DATABASE="${OUTPUT}/radioentries.db"
    fi
    if [ -f "$DATABASE" ]; then
      echo -e "${RED}Database already exists.${NC}"
      exit 1
    fi
    init
    ;;
  remove)
    echo "Functionality not implemented yet."
    exit 0
    ;;
  *)
    echo "No valid commands given"
    exit 1
esac
