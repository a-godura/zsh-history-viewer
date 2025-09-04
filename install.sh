#!/bin/bash

# Universal Installer for the Zsh FZF History Viewer
# This script detects if Oh My Zsh is installed and provides the appropriate
# installation method. It also includes flags for forcing a standard
# installation and for uninstalling the script.

# --- Configuration ---
SCRIPT_NAME="history-viewer"
SOURCE_FILE="${SCRIPT_NAME}.zsh" # The script file to be installed
ZSHRC_FILE="$HOME/.zshrc"

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Installation Functions ---

# Function to handle Oh My Zsh plugin installation
install_for_oh_my_zsh() {
    echo "-> Found Oh My Zsh. Installing as a plugin..."
    
    OMZ_CUSTOM_PLUGINS="$HOME/.oh-my-zsh/custom/plugins"
    PLUGIN_INSTALL_DIR="$OMZ_CUSTOM_PLUGINS/$SCRIPT_NAME"
    PLUGIN_TARGET_FILE="$PLUGIN_INSTALL_DIR/$SCRIPT_NAME.plugin.zsh"

    # 1. Create the plugin directory.
    echo "   Creating plugin directory..."
    mkdir -p "$PLUGIN_INSTALL_DIR"

    # 2. Copy the source script, renaming it with the .plugin.zsh extension.
    echo "   Copying script to $PLUGIN_TARGET_FILE..."
    cp "$SOURCE_FILE" "$PLUGIN_TARGET_FILE"

    # 3. Add the plugin to the .zshrc file.
    echo "   Attempting to activate '$SCRIPT_NAME' in $ZSHRC_FILE..."
    if grep -q "plugins=(.*$SCRIPT_NAME.*)" "$ZSHRC_FILE"; then
      echo "   Plugin '$SCRIPT_NAME' is already activated in your .zshrc file."
    else
      echo "   Adding '$SCRIPT_NAME' to the plugins list..."
      sed -i.bak "s/plugins=(/plugins=($SCRIPT_NAME /" "$ZSHRC_FILE"
      echo "   Successfully added the plugin. A backup of your .zshrc was created at $ZSHRC_FILE.bak"
    fi
}

# Function to handle standard Zsh installation
install_for_standard_zsh() {
    echo "-> Installing for standard Zsh..."

    INSTALL_DIR="$HOME/.${SCRIPT_NAME}"
    TARGET_FILE="$INSTALL_DIR/${SCRIPT_NAME}.zsh"
    SOURCE_LINE="source \"$TARGET_FILE\""

    # 1. Create the installation directory.
    echo "   Creating installation directory at $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"

    # 2. Copy the source script.
    echo "   Copying script to $TARGET_FILE..."
    cp "$SOURCE_FILE" "$TARGET_FILE"

    # 3. Add the source line to the .zshrc file.
    echo "   Attempting to add source line to $ZSHRC_FILE..."
    if grep -q "source .*/${SCRIPT_NAME}.zsh" "$ZSHRC_FILE"; then
        echo "   Source line already exists in your .zshrc file."
    else
        echo "   Appending source line to your .zshrc file..."
        echo "# Load Zsh FZF History Viewer" >> "$ZSHRC_FILE"
        echo "$SOURCE_LINE" >> "$ZSHRC_FILE"
    fi
}

# --- Uninstallation Function ---
uninstall_script() {
    echo "-> Attempting to uninstall Zsh FZF History Viewer..."
    local uninstalled=false
    
    # --- Uninstall Oh My Zsh Plugin Version ---
    OMZ_PLUGIN_DIR="$HOME/.oh-my-zsh/custom/plugins/$SCRIPT_NAME"
    if [ -d "$OMZ_PLUGIN_DIR" ]; then
        echo "   Found Oh My Zsh plugin installation."
        echo "   Removing '$SCRIPT_NAME' from plugins list in $ZSHRC_FILE..."
        # This sed command finds the line with the plugins array and removes our script name.
        # It handles surrounding whitespace to avoid leaving double spaces.
        sed -i.bak -E "/^plugins=\(/ s/\s*\b${SCRIPT_NAME}\b//g" "$ZSHRC_FILE"
        
        echo "   Deleting plugin directory: $OMZ_PLUGIN_DIR..."
        rm -rf "$OMZ_PLUGIN_DIR"
        uninstalled=true
    fi

    # --- Uninstall Standard Zsh Version ---
    STANDARD_INSTALL_DIR="$HOME/.$SCRIPT_NAME"
    if [ -d "$STANDARD_INSTALL_DIR" ]; then
        echo "   Found standard Zsh installation."
        echo "   Removing source line from $ZSHRC_FILE..."
        # Use sed to delete both the source line and the comment above it.
        sed -i.bak -e "/# Load Zsh FZF History Viewer/d" -e "/source.*${SCRIPT_NAME}.zsh/d" "$ZSHRC_FILE"

        echo "   Deleting installation directory: $STANDARD_INSTALL_DIR..."
        rm -rf "$STANDARD_INSTALL_DIR"
        uninstalled=true
    fi

    if [ "$uninstalled" = false ]; then
        echo "   No installation found."
    else
        echo "✅ Uninstallation complete!"
    fi
}


# --- Main Logic ---

# Check for an '--uninstall' flag first.
if [[ "$1" == "--uninstall" ]]; then
    uninstall_script
    echo "Please restart your terminal or run 'source ~/.zshrc' for changes to take effect."
    exit 0
fi

echo "Starting installation for Zsh FZF History Viewer..."
echo "----------------------------------------------------"

# --- Prerequisite Checks ---
# 1. Check for fzf command
if ! command -v fzf >/dev/null; then
  echo "❌ Error: 'fzf' is not installed or not in your PATH."
  echo "   This script requires fzf to function."
  echo "   On macOS, you can install it with: brew install fzf"
  echo "   On other systems, please see the fzf repository for instructions."
  exit 1
fi

# 2. Check for the source script file
if [ ! -f "$SOURCE_FILE" ]; then
    echo "❌ Error: The script source file '$SOURCE_FILE' was not found."
    echo "   Please run this installer from the same directory as the script."
    exit 1
fi

# Check for a '--force' flag to skip OMZ detection.
FORCE_STANDARD=false
if [[ "$1" == "--force" ]]; then
    FORCE_STANDARD=true
    echo "-> --force flag detected. Forcing standard Zsh installation."
fi

# Detect which installation path to take.
if [[ "$FORCE_STANDARD" = true ]]; then
    install_for_standard_zsh
elif [ -d "$HOME/.oh-my-zsh" ]; then
    install_for_oh_my_zsh
else
    echo "-> Oh My Zsh not found."
    echo "   This script can be installed for a standard Zsh setup instead."
    read -p "   Would you like to continue with a standard installation? (y/n) " -n 1 -r
    echo # Move to a new line after user input
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_for_standard_zsh
    else
        echo "   Installation cancelled by user."
        exit 0
    fi
fi

# --- Final Instructions ---
echo ""
echo "----------------------------------------------------"
echo "✅ Installation complete!"
echo "Please restart your terminal or run 'source ~/.zshrc' for the changes to take effect."

