###
#
# Zsh FZF History Viewer Plugin
#
# ------------------------------------------------------------------------------
#
#  Architectural Overview for a Bash-Proficient Software Engineer
#
# This script creates an interactive, fuzzy-searchable command history viewer
# that integrates directly into the Zsh command line. To achieve this, it
# acts as the "glue code" between several powerful shell technologies: Zsh's
# Line Editor (ZLE), the `fzf` command-line tool, the `precmd` hook, and the
# standard `fc` history command.
#
# 1. Zsh Line Editor (ZLE):
#    Think of ZLE as Bash's "readline" on steroids. It's the part of the shell
#    responsible for handling everything you type on the command line before you
#    hit Enter. Unlike readline, ZLE is deeply extensible. We can define custom
#    functions, called "widgets," and then bind them to any key combination.
#    This is the core mechanism we use. Instead of `Ctrl+L` just typing a
#    character, we're telling ZLE, "When you see Ctrl+L, run our custom
#    `_custom_history_widget` function instead."
#
# 2. Oh My Zsh Plugin System:
#    Oh My Zsh is simply a configuration framework. Its "plugin" system is a
#    convention for sourcing (i.e., executing) script files at shell startup.
#    By naming this file `*.plugin.zsh` and placing it in the correct directory,
#    Oh My Zsh finds it and runs it when you open a new terminal. This is how
#    our widget function and key binding are defined and made available.
#
# 3. `fzf` (Fuzzy Finder):
#    `fzf` is the star of the show, but it's an external, standalone program.
#    It's a text filter that reads lines from standard input, displays an
#    interactive UI for the user to select one or more lines, and then prints
#    the selected lines to standard output. Our script's main job is to prepare
#    the command history and pipe it into `fzf`.
#
# 4. `precmd` Hook:
#    Zsh has a hook system that allows functions to be run at specific points
#    in the shell's lifecycle. `precmd_functions` is an array of function names
#    that Zsh executes right before it displays a new prompt. We add a function
#    to this hook to re-apply our key binding before every prompt. This is a
#    robust technique to prevent other plugins (like zsh-autosuggestions) from
#    overriding our `Ctrl+L` binding.
#
# Putting It All Together:
# When the plugin is sourced, it adds `_history_viewer_apply_keybind` to the
# `precmd_functions` array. Just before the next prompt, Zsh runs this function,
# which defines our widget and binds it to `Ctrl+L`. When the user presses
# `Ctrl+L`, ZLE executes `_custom_history_widget`, which in turn calls
# `_history_viewer_ui`. This UI function calls `fc` to get a list of the last
# 1000 commands and pipes it into `fzf`. `fzf` takes over the screen, displaying
# its interactive UI. The user searches and selects a command, pressing either
# `Enter` (for editing) or `Ctrl+X` (for execution). When `fzf` exits, it
# prints the selected command and which key was pressed. Our script captures
# this, inspects the key, and uses ZLE's built-in variables (`BUFFER`) and
# commands (`zle accept-line`) to either place the command on the prompt for
# editing or execute it directly.
#
###


# --- The UI Function ---
# This function is the core of the plugin, responsible for launching fzf and
# handling its output to manipulate the command line buffer.
function _history_viewer_ui() {
  local initial_query=$1

  # --- Prerequisite Check ---
  # Ensure the fzf command is available in the user's PATH. If not, print
  # an error and abort to prevent the script from failing.
  if ! command -v fzf >/dev/null; then
    echo "fzf is not installed. Please run 'brew install fzf' (macOS) or install it for your system to use the history viewer."
    return 1
  fi

  # --- History Formatting and FZF Invocation ---
  # The history is now formatted line-by-line in a Zsh `while` loop for maximum reliability.
  local result
  result=$(
    (
      # Use an associative array to track commands we've already seen.
      typeset -A seen_commands

      # 1. Print a fixed-width header for the columns.
      printf "%-8s %-7s %-7s %s\n" "ID" "DATE" "TIME" "COMMAND";
      
      # 2. Use `fc -lrf` which provides a human-readable timestamp, making it
      #    more portable than relying on UNIX epoch flags which vary by OS.
      fc -lrf -1000 | while read -r line; do
        
        # Use a robust Zsh-native method to split the line into words.
        local -a parts=(${(z)line})

        # Skip malformed lines. A valid line has at least an ID, date, time, and command part.
        if ((${#parts[@]} < 4)); then
            continue
        fi

        local id=${parts[1]}
        local full_date=${parts[2]} # e.g., 09/04/2025
        local time=${parts[3]}      # e.g., 11:51
        
        # Re-join the remaining parts to form the complete original command.
        local command=${(j: :)parts[4,-1]}

        # --- DUPLICATE FILTERING ---
        # If we have already seen this command, skip this older entry.
        # Since history is in reverse order, the first time we see a command is the latest.
        if [[ -n "${seen_commands[$command]}" ]]; then
            continue
        fi
        # Mark this command as seen to filter out any older duplicates.
        seen_commands[$command]=1
        # --- END FILTERING ---

        # Skip any line that doesn't parse into a numeric ID.
        if ! [[ "$id" =~ ^[0-9]+$ ]]; then
            continue
        fi
        
        # Use Zsh Parameter Expansion to remove the year from the date string.
        # This is faster and more reliable than calling `sed`.
        # It removes the last '/' and everything after it.
        local short_date=${full_date%/*}
        
        # Print the fully formatted line, matching the header widths.
        printf "%-8s %-7s %-7s %s\n" "$id" "$short_date" "$time" "$command"
      done
    ) | fzf --height 100% --border --prompt="󰍉 > " \
          --header="[Tab] to Select, [Enter] to Edit, [CTRL+X] to Execute" \
          --query "$initial_query" \
          --expect=ctrl-x --multi \
          --header-lines=1 # This option freezes the first line as a permanent header.
  )

  # --- Cancellation Guard ---
  # If `result` is empty, it means the user cancelled fzf (e.g., via Esc or Ctrl+C).
  if [[ -z "$result" ]]; then
    return
  fi

  # --- Processing FZF Output ---
  # We now parse the multi-line output from `fzf`.
  local key=$(echo "$result" | head -n 1)
  local selected_lines=$(echo "$result" | tail -n +2)

  # Guard in case the selection is somehow empty.
  if [[ -z "$selected_lines" ]]; then
    return
  fi

  # Use `sed` to strip the ID, DATE, and TIME columns. This regex is updated
  # to match the new column order.
  local command=$(echo "$selected_lines" | \
    sed -E 's/^[[:space:]]*[0-9]+[[:space:]]+[0-9\/]+[[:space:]]+[0-9:]{5}[[:space:]]+//')

  # A final guard in case the command is somehow empty after processing.
  if [[ -z "$command" ]]; then
    return
  fi

  # --- Action Dispatch ---
  # Based on the key pressed, we decide what to do with the selected command(s).
  if [[ "$key" == "ctrl-x" ]]; then
    # If Ctrl+X was pressed, we execute the command(s) directly.
    BUFFER="$command"
    zle accept-line
  else
    # If Enter was pressed (or any other key), we only place the command(s) in the buffer for editing.
    BUFFER="$command"
    zle .redisplay
  fi
}

# --- The ZLE Widget ---
# This is a simple wrapper function that ZLE will call. Its only job is to
# launch our main UI function with the current command line content.
function _custom_history_widget() {
  _history_viewer_ui "$BUFFER"
}

# --- Robust Key Binding Function ---
# This function is designed to be run by the `precmd` hook. It ensures our
# widget and keybind are always active, even if another plugin tries to
# override them.
_history_viewer_apply_keybind() {
    # `zle -N ...`: This command defines a new ZLE widget. It gives it the
    # user-facing name `history-viewer-widget` and links it to our shell
    # function `_custom_history_widget`.
    zle -N history-viewer-widget _custom_history_widget
    # `bindkey '^L' ...`: This command creates the key binding. It tells Zsh
    # that whenever the key sequence `^L` (Ctrl+L) is detected, it should

    # execute our newly defined widget.
    bindkey '^L' history-viewer-widget
}

# --- Hook Registration ---
# This ensures our key binding function is added to the `precmd_functions`
# array, which Zsh executes before each prompt. The `if` statement prevents
# it from being added multiple times.
if [[ -z "${precmd_functions[(r)_history_viewer_apply_keybind]}" ]]; then
    precmd_functions+=(_history_viewer_apply_keybind)
fi
