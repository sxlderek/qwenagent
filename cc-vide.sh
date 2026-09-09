#!/usr/bin/env bash
# cc-vide.sh - Batch convert video files to MP4 with hardware encoding priority

set -euo pipefail

# Enable nullglob to prevent loops from choking on empty directories
shopt -s nullglob

# Include getopts_long library (embedded)
getopts_long() {
    : "${1:?Missing required parameter -- long optspec}"
    : "${2:?Missing required parameter -- variable name}"

    local optspec_short="${1%% *}"
    local optspec_long="${1#* }"
    local optvar="${2}"

    shift 2

    if [[ "${#}" == 0 ]]; then
        local args=()
        local -i start_index=0
        local -i end_index=$(( ${#BASH_ARGV[@]} - 1 ))

        # Minimise the number of times `declare -f` is executed
        if [[ -n "${FUNCNAME[1]}" ]]; then
            if [[ "${FUNCNAME[1]}" == "( anon )" ]] \
                    || declare -f "${FUNCNAME[1]}" > /dev/null 2>&1; then
                if ! shopt -q extdebug; then
                    echo "${BASH_SOURCE[1]}: line ${BASH_LINENO[0]}:" \
                    "${FUNCNAME[0]} failed to detect supplied arguments" \
                    "-- enable extdebug or pass arguments explicitly" >&2
                    return 2
                fi
                start_index=${BASH_ARGC[0]}
                end_index=$(( start_index + BASH_ARGC[1] - 1 ))
            fi
        fi

        for (( i = end_index; i >= start_index; i-- )); do
            args+=("${BASH_ARGV[i]}")
        done
        set -- "${args[@]}"
    fi

    # Sanitize and normalize short optspec
    optspec_short="${optspec_short//-:}"
    optspec_short="${optspec_short//-}"
    if [[ -n "${!OPTIND:-}" && "${!OPTIND:0:2}" == "--" ]]; then
        optspec_short+='-:'
    fi


    builtin getopts -- "${optspec_short}" "${optvar}" "${@}" || return ${?}
    [[ "${!optvar}" == '-' ]] || return 0

    printf -v "${optvar}" "%s" "${OPTARG%%=*}"

    if [[ " ${optspec_long} " == *" ${!optvar}: "* ]]; then
        OPTARG="${OPTARG#"${!optvar}"}"
        OPTARG="${OPTARG#=}"

        # Missing argument
        if [[ -z "${OPTARG}" ]]; then
            if [[ -n "${!OPTIND:-}" ]]; then
                OPTARG="${!OPTIND}" && OPTIND=$(( OPTIND + 1 ))
            elif [[ "${optspec_short:0:1}" == ':' ]]; then
                OPTARG="${!optvar}" && printf -v "${optvar}" ':'
            else
                [[ "${OPTERR}" == 0 ]] || \
                    echo "${0}: option requires an argument -- ${!optvar}" >&2
                unset OPTARG && printf -v "${optvar}" '?'
            fi
        fi
    elif [[ " ${optspec_long} " == *" ${!optvar} "* ]]; then
        unset OPTARG
        declare -g OPTARG
    else
        # Invalid option
        if [[ "${optspec_short:0:1}" == ':' ]]; then
            OPTARG="${!optvar}"
        else
            [[ "${OPTERR}" == 0 ]] || echo "${0}: illegal option -- ${!optvar}" >&2
            unset OPTARG
        fi
        printf -v "${optvar}" '?'
    fi
}

# Show usage help
show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Batch convert all video files in the current directory to MP4.

Options:
  -a              Start the video conversion
  --help          Show this help message

Description:
  This script converts video files to MP4 format with hardware encoding priority:
  - NVIDIA NVENC (hevc_nvenc) > Intel QSV (hevc_qsv) > CPU (libx265)

  Output files are saved to ./_out
  Successfully converted files are moved to ./_bak
  Failed conversions are moved to ./_err

Examples:
  $(basename "$0") -a         Start conversion
  $(basename "$0") --help     Show this help
EOF
}

# Check for required tools
check_dependencies() {
    local missing=0
    
    if ! command -v ffmpeg &>/dev/null; then
        echo "Error: ffmpeg is not installed or not in PATH." >&2
        missing=1
    fi
    
    if ! command -v ffprobe &>/dev/null; then
        echo "Error: ffprobe is not installed or not in PATH." >&2
        missing=1
    fi
    
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is not installed or not in PATH." >&2
        missing=1
    fi
    
    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
}

# Function to normalize/fix common video extensions
normalize_extension() {
    local file="$1"
    local ext="${file##*.}"
    local base="${file%.*}"
    local new_ext=""
    local new_file=""
    
    # Convert extension to lowercase for comparison
    local ext_lower="${ext,,}"
    
    case "$ext_lower" in
        mpg|mpeg)
            # .mpeg -> .mpg, .MPG -> .mpg
            new_ext="mpg"
            ;;
        asf)
            # .asf -> .wmv
            new_ext="wmv"
            ;;
        mov|m4v)
            # .mov and .m4v -> .mp4
            new_ext="mp4"
            ;;
        *)
            # For other extensions, just lowercase if needed
            if [[ "$ext" != "$ext_lower" ]]; then
                new_ext="$ext_lower"
            else
                # No change needed
                NORMALIZED_FILE="$file"
                return 0
            fi
            ;;
    esac
    
    new_file="${base}.${new_ext}"
    
    # Only rename if the new filename is different
    if [[ "$file" != "$new_file" ]]; then
        if [[ -f "$new_file" ]]; then
            # Target file already exists, add suffix to avoid collision
            local counter=1
            while [[ -f "${base}_${counter}.${new_ext}" ]]; do
                counter=$((counter + 1))
            done
            new_file="${base}_${counter}.${new_ext}"
        fi
        mv -- "$file" "$new_file"
        echo "Renamed: $file -> $new_file"
    fi
    # Return the new filename via a global variable
    NORMALIZED_FILE="$new_file"
}

# Function to truncate filename to 80 characters using awk (safe for multi-byte UTF-8)
truncate_filename() {
    local input="$1"
    echo "$input" | awk '{print substr($0,1,80)}'
}

# Function to generate unique filename if collision exists
generate_unique_filename() {
    local base="$1"
    local ext="$2"
    local out_dir="$3"
    local target="${out_dir}/${base}.${ext}"
    
    if [[ ! -e "$target" ]]; then
        echo "$base"
        return
    fi
    
    local counter=1
    while true; do
        local suffix
        suffix=$(printf "%03d" "$counter")
        local new_base="${base}_${suffix}"
        target="${out_dir}/${new_base}.${ext}"
        if [[ ! -e "$target" ]]; then
            echo "$new_base"
            return
        fi
        counter=$((counter + 1))
    done
}

# Function to detect best available encoder
detect_encoder() {
    # Check for NVIDIA NVENC
    if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "hevc_nvenc"; then
        echo "nvenc"
        return
    fi
    
    # Check for Intel QSV
    if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "hevc_qsv"; then
        echo "qsv"
        return
    fi
    
    # Fallback to CPU
    echo "cpu"
}

# Function to get encoder flags based on detected encoder
get_encoder_flags() {
    local encoder_type="$1"
    
    case "$encoder_type" in
        nvenc)
            # CRITICAL for NVENC: strict CQ rate control
            echo "-c:v hevc_nvenc -preset medium -rc vbr -cq 32 -b:v 0"
            ;;
        qsv)
            echo "-c:v hevc_qsv -preset medium -cq 32"
            ;;
        cpu)
            echo "-c:v libx265 -preset medium -crf 26"
            ;;
    esac
}

# Function to parse audio streams and build map arguments
build_audio_map() {
    local input_file="$1"
    local -n audio_map_ref=$2
    local -n audio_codec_ref=$3
    
    # Get audio stream info using ffprobe
    local stream_info
    stream_info=$(ffprobe -hide_banner -select_streams a -show_entries stream=index:stream_tags=language:stream=disposition:default -of json "$input_file" 2>/dev/null)
    
    # Count total audio streams
    local total_streams
    total_streams=$(echo "$stream_info" | jq -r '.streams | length')
    
    if [[ "$total_streams" -eq 0 ]]; then
        return
    fi
    
    if [[ "$total_streams" -eq 1 ]]; then
        # Only 1 audio track, keep it
        audio_map_ref+=("-map" "0:a:0")
        audio_codec_ref="-c:a aac -b:a 128k"
        return
    fi
    
    # Multiple audio tracks - look for default, English, or Chinese
    local found_preferred=0
    local first_index=""
    
    for ((i=0; i<total_streams; i++)); do
        local index language is_default
        index=$(echo "$stream_info" | jq -r ".streams[$i].index")
        language=$(echo "$stream_info" | jq -r ".streams[$i].tags.language // \"\"")
        is_default=$(echo "$stream_info" | jq -r ".streams[$i].disposition.default // 0")
        
        # Store first index as fallback
        if [[ -z "$first_index" ]]; then
            first_index="$index"
        fi
        
        # Check if this is a preferred track
        if [[ "$is_default" -eq 1 ]] || [[ "$language" == "eng" ]] || [[ "$language" == "zho" ]] || [[ "$language" == "chi" ]]; then
            audio_map_ref+=("-map" "0:a:$index")
            found_preferred=1
        fi
    done
    
    # If no preferred tracks found, use first track
    if [[ "$found_preferred" -eq 0 ]] && [[ -n "$first_index" ]]; then
        audio_map_ref+=("-map" "0:a:$first_index")
    fi
    
    audio_codec_ref="-c:a aac -b:a 128k"
}

# Function to parse subtitle streams and build map arguments
build_subtitle_map() {
    local input_file="$1"
    local -n subtitle_map_ref=$2
    local -n subtitle_codec_ref=$3
    
    # Get subtitle stream info using ffprobe
    local stream_info
    stream_info=$(ffprobe -hide_banner -select_streams s -show_entries stream=index:stream_tags=language:stream=disposition:default -of json "$input_file" 2>/dev/null)
    
    # Count total subtitle streams
    local total_streams
    total_streams=$(echo "$stream_info" | jq -r '.streams | length')
    
    if [[ "$total_streams" -eq 0 ]]; then
        # No subtitles, omit subtitle flags entirely
        return
    fi
    
    if [[ "$total_streams" -eq 1 ]]; then
        # Only 1 subtitle track, keep it
        subtitle_map_ref+=("-map" "0:s:0")
        subtitle_codec_ref="-c:s mov_text"
        return
    fi
    
    # Multiple subtitle tracks - look for default, English, or Chinese
    local found_preferred=0
    local first_index=""
    
    for ((i=0; i<total_streams; i++)); do
        local index language is_default
        index=$(echo "$stream_info" | jq -r ".streams[$i].index")
        language=$(echo "$stream_info" | jq -r ".streams[$i].tags.language // \"\"")
        is_default=$(echo "$stream_info" | jq -r ".streams[$i].disposition.default // 0")
        
        # Store first index as fallback
        if [[ -z "$first_index" ]]; then
            first_index="$index"
        fi
        
        # Check if this is a preferred track
        if [[ "$is_default" -eq 1 ]] || [[ "$language" == "eng" ]] || [[ "$language" == "zho" ]] || [[ "$language" == "chi" ]]; then
            subtitle_map_ref+=("-map" "0:s:$index")
            found_preferred=1
        fi
    done
    
    # If no preferred tracks found, use first track
    if [[ "$found_preferred" -eq 0 ]] && [[ -n "$first_index" ]]; then
        subtitle_map_ref+=("-map" "0:s:$first_index")
    fi
    
    subtitle_codec_ref="-c:s mov_text"
}

# Main processing loop
process_files() {
    # Create output and backup directories
    mkdir -p "./_out" "./_bak" "./_err"
    
    local encoder_type
    encoder_type=$(detect_encoder)
    
    echo "Using encoder: $encoder_type"
    
    local encoder_flags
    encoder_flags=$(get_encoder_flags "$encoder_type")
    
    # Video extensions to process (including original extensions that may need normalization)
    local video_extensions=("mp4" "mkv" "avi" "mov" "wmv" "flv" "webm" "m4v" "mpeg" "mpg" "3gp" "asf")
    
    # Collect all video files
    local video_files=()
    for ext in "${video_extensions[@]}"; do
        for file in *."$ext" *."${ext^^}"; do
            if [[ -f "$file" ]]; then
                video_files+=("$file")
            fi
        done
    done
    
    # Remove duplicates and sort
    local unique_files=()
    declare -A seen_files
    for file in "${video_files[@]}"; do
        if [[ -z "${seen_files[$file]:-}" ]]; then
            seen_files["$file"]=1
            unique_files+=("$file")
        fi
    done
    
    if [[ ${#unique_files[@]} -eq 0 ]]; then
        echo "No video files found in current directory."
        return
    fi
    
    for input_file in "${unique_files[@]}"; do
        echo ""
        echo "Processing: $input_file"
        
        # Normalize/fix extension before conversion
        NORMALIZED_FILE=""
        normalize_extension "$input_file"
        input_file="$NORMALIZED_FILE"
        
        # Get filename without extension
        local filename_no_ext
        filename_no_ext="${input_file%.*}"
        
        # Truncate filename to 80 characters using awk
        local truncated_name
        truncated_name=$(truncate_filename "$filename_no_ext")
        
        # Generate unique filename
        local unique_name
        unique_name=$(generate_unique_filename "$truncated_name" "mp4" "./_out")
        
        local output_file="./_out/${unique_name}.mp4"
        
        # Build audio map
        local audio_map=()
        local audio_codec=""
        build_audio_map "$input_file" audio_map audio_codec
        
        # Build subtitle map
        local subtitle_map=()
        local subtitle_codec=""
        build_subtitle_map "$input_file" subtitle_map subtitle_codec
        
        # Build FFmpeg command array
        local ffmpeg_cmd=(
            ffmpeg -hide_banner
            -i "$input_file"
            -fflags "+genpts+discardcorrupt"
            -err_detect ignore_err
            $encoder_flags
            -vf "scale='min(1280,iw)':'min(720,ih)':force_original_aspect_ratio=decrease"
        )
        
        # Add audio mapping if any audio streams exist
        if [[ ${#audio_map[@]} -gt 0 ]]; then
            ffmpeg_cmd+=("${audio_map[@]}" "$audio_codec")
        fi
        
        # Add subtitle mapping if any subtitle streams exist
        if [[ ${#subtitle_map[@]} -gt 0 ]]; then
            ffmpeg_cmd+=("${subtitle_map[@]}" "$subtitle_codec")
        fi
        
        # Add output file
        ffmpeg_cmd+=("$output_file")
        
        # Echo the command
        echo "Running: ${ffmpeg_cmd[*]}"
        
        # Execute FFmpeg
        if "${ffmpeg_cmd[@]}"; then
            echo "Success: $input_file -> $output_file"
            mv "$input_file" "./_bak/"
        else
            echo "Failed: $input_file"
            mv "$input_file" "./_err/"
        fi
    done
}

# Main entry point
main() {
    # No arguments: show usage immediately
    if [[ $# -eq 0 ]]; then
        show_usage
        return 0
    fi
    
    local opt
    local OPTIND=1
    OPTARG=""
    
    # Parse arguments using getopts_long (explicitly pass "$@")
    while getopts_long "a help" opt "$@"; do
        case "$opt" in
            a)
                check_dependencies
                process_files
                echo ""
                echo "Batch conversion complete."
                return 0
                ;;
            help)
                show_usage
                return 0
                ;;
            \?)
                show_usage
                return 1
                ;;
        esac
    done
    
    # Unknown option handled by getopts_long
    show_usage
    return 1
}

# Run main function
main "$@"
