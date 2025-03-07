#!/bin/bash

# Check if running as root (optional, for sudo commands)
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo for package installation."
fi

# Update package list and install dependencies
echo "Installing dependencies via apt-get..."
sudo apt update
sudo apt install -y sdcv xsel libnotify-bin python3-pyglossary curl wget dictzip

# Create Stardict dictionary directory
echo "Setting up dictionary directory..."
rm -rf ~/.stardict
mkdir -p ~/.stardict/dic
cd ~/.stardict/dic

# Download English-to-Persian SQL and convert
echo "Downloading English-to-Persian SQL database..."
curl -L -o EnglishPersianWordDatabase.sql https://raw.githubusercontent.com/semnan-university-ai/English-Persian-Word-Database/master/EnglishPersianWordDatabase.sql
echo "Extracting English-to-Persian to text format (UTF-8)..."
grep "('" EnglishPersianWordDatabase.sql | sed "s/\\\'/\"/g" | sed "s/.*('[0-9]*','[0-9]*','[^']*','\([^']*\)','\([^']*\)');/\1\t\2/" | grep -v "^$" | iconv -t UTF-8 > eng-to-per.txt
echo "Sample of eng-to-per.txt for debugging:"
head eng-to-per.txt
echo "Converting English-to-Persian to Stardict format..."
#mkdir -p eng-to-per_stardict
pyglossary eng-to-per.txt eng-to-per_stardict --write-format=Stardict --source-lang=English --target-lang=Persian --name=Eng2Per -v5 --utf8-check
rm EnglishPersianWordDatabase.sql

# Reverse for Persian-to-English
echo "Creating Persian-to-English dictionary by reversing English-to-Persian..."
awk -F'\t' '{print $2"\t"$1}' eng-to-per.txt | grep -v "^$" | iconv -t UTF-8 > per-to-eng.txt
echo "Sample of per-to-eng.txt for debugging:"
head per-to-eng.txt
echo "Converting Persian-to-English to Stardict format..."
#mkdir -p per-to-eng_stardict
pyglossary per-to-eng.txt per-to-eng_stardict --write-format=Stardict --source-lang=Persian --target-lang=English --name=Per2Eng -v5 --utf8-check
rm per-to-eng.txt eng-to-per.txt

# List available dictionaries for debugging
echo "Listing available dictionaries for verification..."
sdcv -l

# Test dictionaries manually with explicit paths
echo "Testing eng-to-per_stardict with 'hello' using explicit path..."
sdcv -u 'Eng2Per (en-fa)' -n "hello"
echo "Testing per-to-eng_stardict with 'سلام' using explicit path..."
sdcv -u 'Per2Eng (fa-en)' -n "سلام"

echo "Creating translation script with notify-send and Google Translate..."
cat << 'EOF' > ~/mani.sh
#!/bin/bash

# Ensure UTF-8 locale for proper Unicode handling
export LC_ALL=C.utf8

word=$(xsel -o | tr '[:upper:]' '[:lower:]' | tr -d '"'| xargs)  # Get highlighted text
first_char="${word:0:1}"  # Get first character (UTF-8 safe)

# Function to query Google Translate
online_query() {
    local input="{\"format\":\"text\",\"from\":\"$2\",\"to\":\"$3\",\"input\":\"$1\",\"options\":{\"sentenceSplitter\":false,\"origin\":\"translation.web\",\"contextResults\":true,\"languageDetection\":true}}"
    local from_lang="$2"
    local target_lang="$3"
    local label="$4"
    local qry=$( echo $1 | sed -E 's/\s{1,}/\+/g' )
    local base_url="https://api.reverso.net/translate/v1/translation"
    local base_syn="https://synonyms.reverso.net/api/v2/search/en/$qry?limit=60&merge=true&rude=false&colloquial=false&exact=true"
    
    # Debug output (optional)
    
    # echo "$input"
    
    # Execute curl and store the result

    local trans=$(curl -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" -s -k --header "Content-Type: application/json" --request POST --data "$input" "$base_url")
    local transSyn=$(curl -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" -s -k --request GET "$base_syn")
    
    # Debug output (optional)

    # echo $transSyn
    
    # Extract translated text from JSON response

    local translated=$(echo "$trans" | jq -r '.translation[0]' 2>/dev/null)
    local parseSyn=$(echo "$transSyn" | jq -r 'if has("error") then "Error present" else .results[0].cluster[:10][].word end')

    # echo $parseSyn

    if [ -n "$translated" ] && [ "$translated" != "null" ]; then
        notify-send "$label" "$translated" -t 15000
    fi

    if [ -n "$parseSyn" ] && [ "$parseSyn" != "null" ]; then
        notify-send "$label" "$parseSyn" -t 15000
    fi
}

# Check if first character is Persian (using case statement)
case "$first_char" in [آابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهیي])  # Common Persian letters
        # Local Persian-to-English with correct dictionary name
        translation=$(sdcv -u "Per2Eng (fa-en)" -n "$word" | grep -A 2 "$word" | tail -n 1)
        if [ -z "$translation" ] || echo "$translation" | grep -q "^--"; then
            translation="Not found"
        fi
        notify-send -a 'Mani' "Per2Eng" "$translation" -t 15000
        # Query Google Translate (Persian to English) in background
        
        online_query "$word" "per" "eng" "GoogleTranslate(Per2Eng)" &
        ;;
    *)
        word=$(echo $word | tr -dc "a-zA-Z0-9[:blank:].()'" | tr -s "'[:blank:]" )
        # Local English-to-Persian with correct dictionary name
        eng_per=$(sdcv -u "Eng2Per (en-fa)" -n "$word" | grep -A 2 "$word" | tail -n 1)
        if [ -z "$eng_per" ] || echo "$eng_per" | grep -q "^--"; then
            eng_per="Not found"
        fi
        notify-send -a 'Mani' -h 'STRING:HH:Hintttt' "Eng2Per" "$eng_per" -t 15000
        # Query Google Translate (English to English and English to Persian) in background
        # online_query "$word" "en" "en" "AI (Eng2Eng)" &
       
        online_query "$word" "eng" "per" "AI (Eng2Per)" &
        ;;
esac
EOF
chmod +x ~/mani.sh

# Set up alias
# echo "Setting up alias 'mani' for sdcv..."
# SHELL_CONFIG="$HOME/.bashrc"  # Default to bash, adjust for zsh if needed
# if [ -n "$ZSH_VERSION" ]; then
#     SHELL_CONFIG="$HOME/.zshrc"
# fi
# echo "alias mani='sdcv'" >> "$SHELL_CONFIG"
# source "$SHELL_CONFIG"

# echo "bind '\"\C-m\":\"~/mani.sh\n\"'" >> "$SHELL_CONFIG"
# source "$SHELL_CONFIG"

# Instructions for shortcut
echo "Installation complete!"
echo "To finish setup, go to Settings > Keyboard > Shortcuts, and add:"
echo "  Name: Offline Translate"
echo "  Command: /home/$USER/mani.sh"
echo "  Shortcut: e.g., Ctrl+Alt+D"
echo "Usage:"
echo "  - Highlight Persian text (e.g., گربه) for Persian-to-English (local + Google)."
echo "  - Highlight English text (e.g., cat) for English-to-Persian (local) and English-to-English (Google)."
echo "  - Local result shows first, then Google Translate follows (internet required)."
echo "Test with: sdcv -u 'Eng2Per (en-fa)' -n hello"
