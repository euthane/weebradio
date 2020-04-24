# weebradio

A command line program for downloading and archiving radio programs. Downloaded audio streams are stored as-is and are accompanied by additional data such as pictures and text in the description.
Supported radio stations (for now) are:

* HiBiKi Radio
* Asobi Store (free)

Required dependencies are: 
* grep 
* curl 
* jq 
* sqlite3 
* xmllint 
* ffmpeg
* youtube-dl

## Usage
```
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
```
## Example
#### HiBiKi
```
# Download the latest episode of 'RoseliaのRADIO SHOUT!'
weebradio download --source hibiki --id Roselia --output /home/eutshiko/radio

# Download the latest episode of 'THE iDOLM@STER Cinderella Girls Radio' that's not in database
weebradio update --source hibiki --id imas_cg --output /home/eutshiko/radio
```

#### Asobi
```
# Assign an id 'シャニラジ' for Asobi list https://asobistore.jp/special/List?tag_seq%5B0%5D=1
weebradio add --source asobi --id シャニラジ --url https://asobistore.jp/special/List?tag_seq%5B0%5D=1 --output /home/eutshiko/radio

# Download the latest episode of 'THE iDOLM@STER Shiny Colors Radio' that's not in database
weebradio update --source asobi --id シャニラジ --output /home/eutshiko/radio
```

```
# Update every radio shows in database (HiBiKi and Asobi store)
weebradio updateAll --output /home/eutshiko/radio
```
