# weebradio

A commandline program for downloading and managing radio programs written in bash. Downloaded audio streams are stored as-is and are accompanied by additional 
Supported radio stations (for now) are:

* HiBiKi Radio
* Asobi Store (free)

Required dependencies are: grep curl jq sqlite3 xmllint ffmpeg

## Usage

weebradio [command] --source <asobi|hibiki> --url <url> --id <id> --output <path> --database <filepath>

Commands:
  download: download latest episode or non-premium Asobi Store episode. Only downloads the audio file.
    For Asobi Store radio shows: This can be used --url "https://asobistore.jp/special/Detail?seq=<Sequence ID for episode>" 
  init: initialize database file.
  add: Pairs an id with a URL (Mainly used in Asobi radio shows)
  update: checks for new episodes and downloads them with additional information such as text and images. Adds radio show to the database if not already.
  updateAll: checks for new episodes for every radio show in the database.


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

### Example
#### HiBiKi
```
# Download the latest episode of RoseliaのRADIO SHOUT!
weebradio download --source hibiki --id Roselia --output /home/eutshiko/radio

# Check for update and download latest episode of THE iDOLM@STER Cinderella Girls Radio with texts and images
weebradio update --source hibiki --id imas_cg --output /home/eutshiko/radio
```

#### Asobi
```
# Assign an id 'シャニラジ' for Asobi list https://asobistore.jp/special/List?tag_seq%5B0%5D=1
weebradio add --source asobi --id シャニラジ --url https://asobistore.jp/special/List?tag_seq%5B0%5D=1 --output /home/eutshiko/radio

# Check for update and download latest episode of THE iDOLM@STER Shiny Colors Radio with texts and images
weebradio update --source asobi --id シャニラジ --output /home/eutshiko/radio
```

```
# Update every radio shows in database (HiBiKi and Asobi store)
weebradio updateAll --output /home/eutshiko/radio
```
