#!/bin/sh

version_number="4.8.1"

# UI

external_menu() {
    rofi "$1" -sort -dmenu -i -width 1500 -p "$2"
}

launcher() {
    [ "$use_external_menu" = "0" ] && [ -z "$1" ] && set -- "+m" "$2"
    [ "$use_external_menu" = "0" ] && fzf "$1" --reverse --cycle --prompt "$2"
    [ "$use_external_menu" = "1" ] && external_menu "$1" "$2"
}

nth() {
    stdin=$(cat -)
    [ -z "$stdin" ] && return 1
    line_count="$(printf "%s\n" "$stdin" | wc -l | tr -d "[:space:]")"
    [ "$line_count" -eq 1 ] && printf "%s" "$stdin" | cut -f2,3 && return 0
    prompt="$1"
    multi_flag=""
    [ $# -ne 1 ] && shift && multi_flag="$1"
    line=$(printf "%s" "$stdin" | cut -f1,3 | tr '\t' ' ' | launcher "$multi_flag" "$prompt" | cut -d " " -f 1)
    [ -n "$line" ] && printf "%s" "$stdin" | grep -E '^'"${line}"'($|[[:space:]])' | cut -f2,3 || exit 1
}

die() {
    printf "\33[2K\r\033[1;31m%s\033[0m\n" "$*" >&2
    exit 1
}

help_info() {
    printf "
    Usage:
    %s [options] [query]
    %s [query] [options]
    %s [options] [query] [options]

    Options:
      -c, --continue
        Continue watching from history
      -d, --download
        Download the video instead of playing it
      -D, --delete
        Delete history
      -s, --syncplay
        Use Syncplay to watch with friends
      -S, --select-nth
        Select nth entry
      -q, --quality
        Specify the video quality
      -v, --vlc
        Use VLC to play the video
      -V, --version
        Show the version of the script
      -h, --help
        Show this help message and exit
      -e, --episode, -r, --range
        Specify the number of episodes to watch
      --dub
        Play dubbed version
      --rofi
        Use rofi instead of fzf for the interactive menu
      --skip
        Use ani-skip to skip the intro of the episode (mpv only)
      --no-detach
        Don't detach the player (useful for in-terminal playback, mpv only)
      --skip-title <title>
        Use given title as ani-skip query
      -U, --update
        Update the script
    Some example usages:
      %s -q 720p banana fish
      %s --skip --skip-title \"one piece\" -S 2 one piece
      %s -d -e 2 cyberpunk edgerunners
      %s --vlc cyberpunk edgerunners -q 1080p -e 4
      %s blue lock -e 5-6
      %s -e \"5 6\" blue lock
    \n" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}" "${0##*/}"
    exit 0
}

version_info() {
    printf "%s\n" "$version_number"
    exit 0
}

update_script() {
    update="$(curl -s -A "$agent" "https://raw.githubusercontent.com/pystardust/ani-cli/master/ani-cli")" || die "Connection error"
    update="$(printf '%s\n' "$update" | diff -u "$0" -)"
    if [ -z "$update" ]; then
        printf "Script is up to date :)\n"
    else
        if printf '%s\n' "$update" | patch "$0" -; then
            printf "Script has been updated\n"
        else
            die "Can't update for some reason!"
        fi
    fi
    exit 0
}

# checks if dependencies are present
dep_ch() {
    for dep; do
        command -v "$dep" >/dev/null || die "Program \"$dep\" not found. Please install it."
    done
}

# SCRAPING

# extract the video links from reponse of embed urls, extract mp4 links form m3u8 lists
get_links() {
    episode_link="$(curl -e "$allanime_refr" -s "https://${allanime_base}$*" -A "$agent" | sed 's|},{|\
|g' | sed -nE 's|.*link":"([^"]*)".*"resolutionStr":"([^"]*)".*|\2 >\1|p;s|.*hls","url":"([^"]*)".*"hardsub_lang":"en-US".*|\1|p')"

    case "$episode_link" in
    *repackager.wixmp.com*)
        extract_link=$(printf "%s" "$episode_link" | cut -d'>' -f2 | sed 's|repackager.wixmp.com/||g;s|\.urlset.*||g')
        for j in $(printf "%s" "$episode_link" | sed -nE 's|.*/,([^/]*),/mp4.*|\1|p' | sed 's|,|\
|g'); do
            printf "%s >%s\n" "$j" "$extract_link" | sed "s|,[^/]*|${j}|g"
        done | sort -nr
        ;;
    *vipanicdn* | *anifastcdn*)
        if printf "%s" "$episode_link" | head -1 | grep -q "original.m3u"; then
            printf "%s" "$episode_link"
        else
            extract_link=$(printf "%s" "$episode_link" | head -1 | cut -d'>' -f2)
            relative_link=$(printf "%s" "$extract_link" | sed 's|[^/]*$||')
            curl -e "$allanime_refr" -s "$extract_link" -A "$agent" | sed 's|^#.*x||g; s|,.*|p|g; /^#/d; $!N; s|\
| >|' | sed "s|>|>${relative_link}|g" | sort -nr
        fi
        ;;
    *) [ -n "$episode_link" ] && printf "%s\n" "$episode_link" ;;
    esac
    [ -z "$ANI_CLI_NON_INTERACTIVE" ] && printf "\033[1;32m%s\033[0m Links Fetched\n" "$provider_name" 1>&2
}

# innitialises provider_name and provider_id. First argument is the provider name, 2nd is the regex that matches that provider's link
provider_init() {
    provider_name=$1
    provider_id=$(printf "%s" "$resp" | sed -n "$2" | head -1 | cut -d':' -f2 | sed 's/../&\
/g' | sed 's/^01$/9/g;s/^08$/0/g;s/^05$/=/g;s/^0a$/2/g;s/^0b$/3/g;s/^0c$/4/g;s/^07$/?/g;s/^00$/8/g;s/^5c$/d/g;s/^0f$/7/g;s/^5e$/f/g;s/^17$/\//g;s/^54$/l/g;s/^09$/1/g;s/^48$/p/g;s/^4f$/w/g;s/^0e$/6/g;s/^5b$/c/g;s/^5d$/e/g;s/^0d$/5/g;s/^53$/k/g;s/^1e$/\&/g;s/^5a$/b/g;s/^59$/a/g;s/^4a$/r/g;s/^4c$/t/g;s/^4e$/v/g;s/^57$/o/g;s/^51$/i/g;' | tr -d '\n' | sed "s/\/clock/\/clock\.json/")
}

# generates links based on given provider
generate_link() {
    case $1 in
    1) provider_init "wixmp" "/Default :/p" ;;     # wixmp(default)(m3u8)(multi) -> (mp4)(multi)
    2) provider_init "dropbox" "/Sak :/p" ;;       # dropbox(mp4)(single)
    3) provider_init "wetransfer" "/Kir :/p" ;;    # wetransfer(mp4)(single)
    4) provider_init "sharepoint" "/S-mp4 :/p" ;;  # sharepoint(mp4)(single)
    *) provider_init "gogoanime" "/Luf-mp4 :/p" ;; # gogoanime(m3u8)(multi)
    esac
    [ -n "$provider_id" ] && get_links "$provider_id"
}

select_quality() {
    case "$1" in
    best) result=$(printf "%s" "$links" | head -n1) ;;
    worst) result=$(printf "%s" "$links" | grep -E '^[0-9]{3,4}' | tail -n1) ;;
    *) result=$(printf "%s" "$links" | grep -m 1 "$1") ;;
    esac
    [ -z "$result" ] && printf "Specified quality not found, defaulting to best\n" 1>&2 && result=$(printf "%s" "$links" | head -n1)
    printf "%s" "$result" | cut -d'>' -f2
}

# gets embed urls, collects direct links into provider files, selects one with desired quality into $episode
get_episode_url() {
    # get the embed urls of the selected episode
    episode_embed_gql="query (\$showId: String!, \$translationType: VaildTranslationTypeEnumType!, \$episodeString: String!) {    episode(        showId: \$showId        translationType: \$translationType        episodeString: \$episodeString    ) {        episodeString sourceUrls    }}"

    resp=$(curl -e "$allanime_refr" -s -G "${allanime_api}/api" --data-urlencode "variables={\"showId\":\"$id\",\"translationType\":\"$mode\",\"episodeString\":\"$ep_no\"}" --data-urlencode "query=$episode_embed_gql" -A "$agent" | tr '{}' '\n' | sed 's|\\u002F|\/|g;s|\\||g' | sed -nE 's|.*sourceUrl":"--([^"]*)".*sourceName":"([^"]*)".*|\2 :\1|p')
    # generate links into sequential files
    cache_dir="$(mktemp -d)"
    providers="1 2 3 4 5"
    for provider in $providers; do
        generate_link "$provider" >"$cache_dir"/"$provider" &
    done
    wait
    # select the link with matching quality
    links=$(cat "$cache_dir"/* | sed 's|^Mp4-||g;/http/!d' | sort -g -r -s)
    rm -r "$cache_dir"
    episode=$(select_quality "$quality")
    [ -z "$episode" ] && die "Episode not released!"
}

# search the query and give results
search_anime() {
    search_gql="query(        \$search: SearchInput        \$limit: Int        \$page: Int        \$translationType: VaildTranslationTypeEnumType        \$countryOrigin: VaildCountryOriginEnumType    ) {    shows(        search: \$search        limit: \$limit        page: \$page        translationType: \$translationType        countryOrigin: \$countryOrigin    ) {        edges {            _id name availableEpisodes __typename       }    }}"

    curl -e "$allanime_refr" -s -G "${allanime_api}/api" --data-urlencode "variables={\"search\":{\"allowAdult\":false,\"allowUnknown\":false,\"query\":\"$1\"},\"limit\":40,\"page\":1,\"translationType\":\"$mode\",\"countryOrigin\":\"ALL\"}" --data-urlencode "query=$search_gql" -A "$agent" | sed 's|Show|\
|g' | sed -nE "s|.*_id\":\"([^\"]*)\",\"name\":\"([^\"]*)\".*${mode}\":([1-9][^,]*).*|\1        \2 (\3 episodes)|p"
}

# get the episodes list of the selected anime
episodes_list() {
    episodes_list_gql="query (\$showId: String!) {    show(        _id: \$showId    ) {        _id availableEpisodesDetail    }}"

    curl -e "$allanime_refr" -s -G "${allanime_api}/api" --data-urlencode "variables={\"showId\":\"$*\"}" --data-urlencode "query=$episodes_list_gql" -A "$agent" | sed -nE "s|.*$mode\":\[([0-9.\",]*)\].*|\1|p" | sed 's|,|\
|g; s|"||g' | sort -n -k 1
}

# PLAYING

process_hist_entry() {
    ep_list=$(episodes_list "$id")
    ep_no=$(printf "%s" "$ep_list" | sed -n "/^${ep_no}$/{n;p;}") 2>/dev/null
    [ -n "$ep_no" ] && printf "%s\t%s - episode %s\n" "$id" "$title" "$ep_no"
}

update_history() {
    if grep -q -- "$id" "$histfile"; then
        sed -E "s/^[^\t]+\t${id}\t/${ep_no}\t${id}\t/" "$histfile" >"${histfile}.new"
    else
        cp "$histfile" "${histfile}.new"
        printf "%s\t%s\t%s\n" "$ep_no" "$id" "$title" >>"${histfile}.new"
    fi
    mv "${histfile}.new" "$histfile"
}

download() {
    case $1 in
    *m3u8*)
        if command -v "yt-dlp" >/dev/null; then
            yt-dlp "$1" --no-skip-unavailable-fragments --fragment-retries infinite -N 16 -o "$download_dir/$2.mp4"
        else
            ffmpeg -loglevel error -stats -i "$1" -c copy "$download_dir/$2.mp4"
        fi
        ;;
    *)
        aria2c --enable-rpc=false --check-certificate=false --continue --summary-interval=0 -x 16 -s 16 "$1" --dir="$download_dir" -o "$2.mp4" --download-result=hide
        ;;
    esac
}

play_episode() {
    aniskip_title="${skip_title:-${title}}"
    [ "$skip_intro" = 1 ] && skip_flag="$(ani-skip "$aniskip_title" "$ep_no")"
    [ -z "$episode" ] && get_episode_url
    # shellcheck disable=SC2086
    case "$player_function" in
    debug)
        [ -z "$ANI_CLI_NON_INTERACTIVE" ] && printf "All links:\n%s\nSelected link:\n" "$links"
        printf "%s\n" "$episode"
        ;;
    mpv*) $([ "$no_detach" = 0 ] && echo "nohup") "$player_function" $skip_flag --force-media-title="${allanime_title}Episode ${ep_no}" "$episode" >/dev/null 2>&1 & ;;
    android_mpv) nohup am start --user 0 -a android.intent.action.VIEW -d "$episode" -n is.xyz.mpv/.MPVActivity >/dev/null 2>&1 & ;;
    android_vlc) nohup am start --user 0 -a android.intent.action.VIEW -d "$episode" -n org.videolan.vlc/org.videolan.vlc.gui.video.VideoPlayerActivity -e "title" "${allanime_title}Episode ${ep_no}" >/dev/null 2>&1 & ;;
    iina) nohup "$player_function" --no-stdin --keep-running --mpv-force-media-title="${allanime_title}Episode ${ep_no}" "$episode" >/dev/null 2>&1 & ;;
    flatpak_mpv) flatpak run io.mpv.Mpv --force-media-title="${allanime_title}Episode ${ep_no}" "$episode" >/dev/null 2>&1 & ;;
    vlc*) nohup "$player_function" --play-and-exit --meta-title="${allanime_title}Episode ${ep_no}" "$episode" >/dev/null 2>&1 & ;;
    *yncpla*) nohup "$player_function" "$episode" -- --force-media-title="${allanime_title}Episode ${ep_no}" >/dev/null 2>&1 & ;;
    download) "$player_function" "$episode" "${allanime_title}Episode ${ep_no}" ;;
    catt) nohup catt cast "$episode" >/dev/null 2>&1 & ;;
    iSH)
        printf "\e]8;;vlc://%s\a~~~~~~~~~~~~~~~~~~~~\n~ Tap to open VLC ~\n~~~~~~~~~~~~~~~~~~~~\e]8;;\a\n" "$episode"
        sleep 5
        ;;
    *) nohup "$player_function" "$episode" >/dev/null 2>&1 & ;;
    esac
    replay="$episode"
    unset episode
    update_history
    [ "$use_external_menu" = "1" ] && wait
}

play() {
    start=$(printf "%s" "$ep_no" | grep -Eo '^(-1|[0-9]+(\.[0-9]+)?)')
    end=$(printf "%s" "$ep_no" | grep -Eo '(-1|[0-9]+(\.[0-9]+)?)$')
    [ "$start" = "-1" ] && ep_no=$(printf "%s" "$ep_list" | tail -n1) && unset start
    [ -z "$end" ] || [ "$end" = "$start" ] && unset start end
    [ "$end" = "-1" ] && end=$(printf "%s" "$ep_list" | tail -n1)
    line_count=$(printf "%s\n" "$ep_no" | wc -l | tr -d "[:space:]")
    if [ "$line_count" != 1 ] || [ -n "$start" ]; then
        [ -z "$start" ] && start=$(printf "%s\n" "$ep_no" | head -n1)
        [ -z "$end" ] && end=$(printf "%s\n" "$ep_no" | tail -n1)
        range=$(printf "%s\n" "$ep_list" | sed -nE "/^${start}\$/,/^${end}\$/p")
        [ -z "$range" ] && die "Invalid range!"
        for i in $range; do
            tput clear
            ep_no=$i
            printf "\33[2K\r\033[1;34mPlaying episode %s...\033[0m\n" "$ep_no"
            play_episode
        done
    else
        play_episode
    fi
    # moves upto stored positon and deletes to end
    [ "$player_function" != "debug" ] && [ "$player_function" != "download" ] && tput rc && tput ed
}

# MAIN

# setup
agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0"
allanime_refr="https://allanime.to"
allanime_base="allanime.day"
allanime_api="https://api.${allanime_base}"
mode="${ANI_CLI_MODE:-sub}"
download_dir="${ANI_CLI_DOWNLOAD_DIR:-.}"
quality="${ANI_CLI_QUALITY:-best}"
case "$(uname -a)" in
*Darwin*) player_function="${ANI_CLI_PLAYER:-iina}" ;;            # mac OS
*ndroid*) player_function="${ANI_CLI_PLAYER:-android_mpv}" ;;     # Android OS (termux)
*steamdeck*) player_function="${ANI_CLI_PLAYER:-flatpak_mpv}" ;;  # steamdeck OS
*MINGW* | *WSL2*) player_function="${ANI_CLI_PLAYER:-mpv.exe}" ;; # Windows OS
*ish*) player_function="${ANI_CLI_PLAYER:-iSH}" ;;                # iOS (iSH)
*) player_function="${ANI_CLI_PLAYER:-mpv}" ;;                    # Linux OS
esac

no_detach="${ANI_CLI_NO_DETACH:-0}"
use_external_menu="${ANI_CLI_EXTERNAL_MENU:-0}"
skip_intro="${ANI_CLI_SKIP_INTRO:-0}"
# shellcheck disable=SC2154
skip_title="$ANI_CLI_SKIP_TITLE"
[ -t 0 ] || use_external_menu=1
hist_dir="${ANI_CLI_HIST_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ani-cli}"
[ ! -d "$hist_dir" ] && mkdir -p "$hist_dir"
histfile="$hist_dir/ani-hsts"
[ ! -f "$histfile" ] && : >"$histfile"
search="${ANI_CLI_DEFAULT_SOURCE:-scrape}"

while [ $# -gt 0 ]; do
    case "$1" in
    -v | --vlc)
        case "$(uname -a)" in
        *ndroid*) player_function="android_vlc" ;;
        MINGW* | *WSL2*) player_function="vlc.exe" ;;
        *ish*) player_function="iSH" ;;
        *) player_function="vlc" ;;
        esac
        ;;
    -s | --syncplay)
        case "$(uname -s)" in
        Darwin*) player_function="/Applications/Syncplay.app/Contents/MacOS/syncplay" ;;
        MINGW* | *Msys)
            export PATH="$PATH":"/c/Program Files (x86)/Syncplay/"
            player_function="syncplay.exe"
            ;;
        *) player_function="syncplay" ;;
        esac
        ;;
    -q | --quality)
        [ $# -lt 2 ] && die "missing argument!"
        quality="$2"
        shift
        ;;
    -S | --select-nth)
        [ $# -lt 2 ] && die "missing argument!"
        index="$2"
        shift
        ;;
    -c | --continue) search=history ;;
    -d | --download) player_function=download ;;
    -D | --delete)
        : >"$histfile"
        exit 0
        ;;
    -V | --version) version_info ;;
    -h | --help) help_info ;;
    -e | --episode | -r | --range)
        [ $# -lt 2 ] && die "missing argument!"
        ep_no="$2"
        [ -n "$index" ] && ANI_CLI_NON_INTERACTIVE=1 #Checks for -S presence
        shift
        ;;
    --dub) mode="dub" ;;
    --no-detach) no_detach=1 ;;
    --rofi) use_external_menu=1 ;;
    --skip) skip_intro=1 ;;
    --skip-title)
        [ $# -lt 2 ] && die "missing argument!"
        skip_title="$2"
        shift
        ;;
    -U | --update) update_script ;;
    *) query="$(printf "%s" "$query $1" | sed "s|^ ||;s| |+|g")" ;;
    esac
    shift
done
[ "$use_external_menu" = "0" ] && multi_selection_flag="${ANI_CLI_MULTI_SELECTION:-"-m"}"
[ "$use_external_menu" = "1" ] && multi_selection_flag="${ANI_CLI_MULTI_SELECTION:-"-multi-select"}"
printf "\33[2K\r\033[1;34mChecking dependencies...\033[0m\n"
dep_ch "curl" "sed" "grep" || true
[ "$skip_intro" = 1 ] && (dep_ch "ani-skip" || true)
if [ -z "$ANI_CLI_NON_INTERACTIVE" ]; then dep_ch fzf || true; fi
case "$player_function" in
debug) ;;
download) dep_ch "ffmpeg" "aria2c" ;;
flatpak*)
    dep_ch "flatpak"
    flatpak info io.mpv.Mpv >/dev/null 2>&1 || die "Program \"mpv (flatpak)\" not found. Please install it."
    ;;
android*) printf "\33[2K\rChecking of players on Android is disabled\n" ;;
*iSH*) printf "\33[2K\rChecking of players on iOS is disabled\n" ;;
*) dep_ch "$player_function" ;;
esac

# searching
case "$search" in
history)
    anime_list=$(while read -r ep_no id title; do process_hist_entry & done <"$histfile")
    wait
    [ -z "$anime_list" ] && die "No unwatched series in history!"
    result=$(printf "%s" "$anime_list" | nl -w 2 | sed 's/^[[:space:]]//' | nth "Select anime: " | cut -f1)
    [ -z "$result" ] && exit 1
    resfile="$(mktemp)"
    grep "$result" "$histfile" >"$resfile"
    read -r ep_no id title <"$resfile"
    ep_list=$(episodes_list "$id")
    ep_no=$(printf "%s" "$ep_list" | sed -n "/^${ep_no}$/{n;p;}") 2>/dev/null
    allanime_title="$(printf "%s" "$title" | cut -d'(' -f1 | tr -d '[:punct:]')"
    ;;
*)
    if [ "$use_external_menu" = "0" ]; then
        while [ -z "$query" ]; do
            printf "\33[2K\r\033[1;36mSearch anime: \033[0m" && read -r query
        done
    else
        [ -z "$query" ] && query=$(printf "" | external_menu "" "Search anime: ")
        [ -z "$query" ] && exit 1
    fi
    query=$(printf "%s" "$query" | sed "s| |+|g")
    anime_list=$(search_anime "$query")
    [ -z "$anime_list" ] && die "No results found!"
    [ "$index" -eq "$index" ] 2>/dev/null && result=$(printf "%s" "$anime_list" | sed -n "${index}p")
    [ -z "$index" ] && result=$(printf "%s" "$anime_list" | nl -w 2 | sed 's/^[[:space:]]//' | nth "Select anime: ")
    [ -z "$result" ] && exit 1
    title=$(printf "%s" "$result" | cut -f2)
    allanime_title="$(printf "%s" "$title" | cut -d'(' -f1 | tr -d '[:punct:]')"
    id=$(printf "%s" "$result" | cut -f1)
    ep_list=$(episodes_list "$id")
    [ -z "$ep_no" ] && ep_no=$(printf "%s" "$ep_list" | nth "Select episode: " "$multi_selection_flag")
    [ -z "$ep_no" ] && exit 1
    ;;
esac

# moves the cursor up one line and clears that line
tput cuu1 && tput el
# stores the positon of cursor
tput sc

# playback & loop
play
[ "$player_function" = "download" ] || [ "$player_function" = "debug" ] && exit 0

while cmd=$(printf "next\nreplay\nprevious\nselect\nchange_quality\nquit" | nth "Playing episode $ep_no of $title... "); do
    case "$cmd" in
    next) ep_no=$(printf "%s" "$ep_list" | sed -n "/^${ep_no}$/{n;p;}") 2>/dev/null ;;
    replay) episode="$replay" ;;
    previous) ep_no=$(printf "%s" "$ep_list" | sed -n "/^${ep_no}$/{g;1!p;};h") 2>/dev/null ;;
    select) ep_no=$(printf "%s" "$ep_list" | nth "Select episode: " "$multi_selection_flag") ;;
    change_quality)
        episode=$(printf "%s" "$links" | launcher)
        quality=$(printf "%s" "$episode" | grep -oE "^[0-9]+")
        episode=$(printf "%s" "$episode" | cut -d'>' -f2)
        ;;
    *) exit 0 ;;
    esac
    [ -z "$ep_no" ] && die "Out of range"
    play
done
