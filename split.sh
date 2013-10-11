#! /bin/bash
#
# Usage: ./split.sh [-a artist] [-y year_regex] [music_dir] [output_dir]
#
# music_dir:
#              Directory to search music/cue files in. Default: .
# output_dir:
#              Directory to put splitted files into. Default: same as music_dir
#
# Small script to batch split & rename music in format flac+.cue
# All .flac with corresponding .cue files will be splitted and put in
#
# [output_dir]/[artist]/[album]/[trackno] - [tracktitle].[typ]
#
# [artist], [album], [trackno] and [tracktitle] will be taken from CUE
# sheet. The only unnecessary tag is [tracktitle], if it is absent, track
# will be renamed to [trackname].[typ]. If any other is absent, the renaming
# will not take place. It should not happen with CUE sheets, though.
#

set -e

while getopts "a:y:" opt; do
     case $opt in
          a) SET_ARTIST="$OPTARG" ;;
          y) YEAR_REGEX="$OPTARG" ;;
     esac
done

shift $((OPTIND - 1))

start_dir=$1
out_dir=$2

[[ $start_dir ]] || start_dir=.
[[ $out_dir ]] || out_dir=$start_dir

[[ $YEAR_REGEX ]] || YEAR_REGEX='^REM *DATE *([0-9]{4})'

typ=flac

warn() { echo -e "$*" 1>&2 ; }
die() { warn "$*" ; exit 1 ; }

move_file() {
     local file=$1
     local new_name=$(basename "$2")
     local target_dir=$(dirname "$2")

     [[ -d "$target_dir" ]] || \
          { mkdir -p "$target_dir" || die "Failed to create $target_dir" ; }

     mv "$track" "$target_dir/$new_name"
}

flactag() {
     local track=$1
     local trackno=$2
     local cue_sheet=$3

     metaflac="metaflac --remove-all-tags --import-tags-from=-"
     fields="TITLE VERSION ALBUM TRACKNUMBER TRACKTOTAL ARTIST
          PERFORMER COPYRIGHT LICENSE ORGANIZATION DESCRIPTION
          GENRE DATE LOCATION CONTACT ISRC"

     TITLE='%t'
     VERSION=''
     ALBUM='%T'
     TRACKNUMBER='%n'
     TRACKTOTAL='%N'
     ARTIST='%c %p'
     PERFORMER='%p'
     COPYRIGHT=''
     LICENSE=''
     ORGANIZATION=''
     DESCRIPTION='%m'
     GENRE='%g'
     DATE=''
     LOCATION=''
     CONTACT=''
     ISRC='%i %u'

     echo "trackno: $trackno"

     (for field in $fields; do
          value=""

          for conv in ${!field}; do
               if [[ $SET_ARTIST ]]; then
                    if [[ $field = ARTIST ]] || [[ $field = PERFORMER ]]; then
                         echo "$field=$SET_ARTIST"
                         break
                    fi
               fi

               value=$(cueprint -n $trackno -t "$conv\n" "$cue_sheet")

               [[ -n "$value" ]] && { echo "$field=$value" ; break ; }
          done

          if [[ $field = DATE ]] && [[ $YEAR ]]; then
               echo "DATE=$YEAR"
          fi

     done) | $metaflac "$track"
}

find "$start_dir" -name '*'.$typ | while read image; do
     cue=${image%$typ}cue
     dir=$(dirname "$image")

     echo "Working in $dir"
     shntool split \
          -f "$cue" \
          -o $typ \
          -d "$out_dir" \
          "$image" || { warn "Splitting '$image' failed"; continue; }

     trackno=0

     # try to guess year from comment
     YEAR=$(sed -nr "s/$YEAR_REGEX/\\1/p" "$cue" | tr -d ' \r\n')

     for track in "$out_dir"/split-track*.$typ; do
          trackno=$((trackno + 1))

          flactag "$track" $trackno "$cue"

          for field in ARTIST TRACKNUMBER ALBUM TITLE; do
               printf -v $field "$(metaflac --show-tag=$field "$track" | \
                    cut -d= -f2 | tr '!/' '_')"
          done

          new_name=$(printf '%02d - %s'.$typ $TRACKNUMBER "$TITLE")

          if [[ -z $TITLE ]]; then
               warn "$track: no TITLE tag"

               new_name=$(printf '%02d'.$typ $TRACKNUMBER)
          fi

          if [[ -z $YEAR ]]; then
               target="$out_dir/$ARTIST/$ALBUM"
          else
               target="$out_dir/$ARTIST/$YEAR - $ALBUM"
          fi

          echo "'$track' -> '$target/$new_name'"
          move_file "$track" "$target/$new_name"
     done
done

