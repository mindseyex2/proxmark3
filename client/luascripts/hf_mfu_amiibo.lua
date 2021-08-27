local cmds = require('commands')
local getopt = require('getopt')
local lib14a = require('read14a')
local utils =  require('utils')
local ansicolors = require('ansicolors')

-- global
local DEBUG = true -- the debug flag
local bxor = bit32.bxor

-- A debug printout-function
local function dbg(args)
    if not DEBUG then return end
    if type(args) == 'table' then
        local i = 1
        while args[i] do
            dbg(args[i])
            i = i+1
        end
    else
        print('###', args)
    end
end
---
-- This is only meant to be used when errors occur
local function oops(err)
    print('ERROR:', err)
    core.clearCommandBuffer()
    return nil, err
end
--
--- Calculate amiibo pwd
local function get_amiibo_pwd(uid)
    local tu = {}
    -- put uid in table
    for k in uid:gmatch"(%x%x)" do
        table.insert(tu, tonumber(k, 16))
    end
    -- generate amiibo password based on this blog
    -- https://nfc.toys/interop-ami.html
    return string.format("%02X%02X%02X%02X",
        bxor(tu[2], bxor(0xaa, tu[4])),
        bxor(tu[3], bxor(0x55, tu[5])),
        bxor(tu[4], bxor(0xaa, tu[6])),
        bxor(tu[5], bxor(0x55, tu[7]))
    )
end
--
--- inject uid into the image
--- you'll need to have this python amiibo utility
--- https://pyamiibo.readthedocs.io/en/latest/
local function injectuid(uid, image, newimage)
    local tu = {}
    -- put uid in table
    for k in uid:gmatch"(%x%x)" do
        table.insert(tu, tonumber(k, 16))
    end
    print('Injecting uid into '..image)
    struid = string.format("%02X %02X %02X %02X %02X %02X %02X",
        tu[1], tu[2], tu[3], tu[4], tu[5], tu[6], tu[7])
    mycmd = '/usr/local/bin/amiibo uid '..image..' "'..struid..'" '..newimage
    print(mycmd)
    res = os.execute(mycmd)
    print(res)
    return nil
end
--
--- firstphase of actions
local function firstphase(key, img)
    print('Restoring image from file: '..img)
    -- restore image
    core.console('hf mfu restore -k FFFFFFFF -f '..img)
    -- cleanup and remove created img file - This should be changed to a generic command to remove files.
    os.execute('rm -f '..img)
    -- write block 3
    core.console('hf mfu wrbl -b 3 -d F110FFEE -k FFFFFFFF')
    -- write block 134
    core.console('hf mfu wrbl -b 134 -d 80800000 -k FFFFFFFF')
    -- write block 133 - new key
    core.console('hf mfu wrbl -b 133 -d '..key..' -k FFFFFFFF')
    -- write block 131
    core.console('hf mfu wrbl -b 131 -d 00000004 -k '..key)
    -- write block 132
    core.console('hf mfu wrbl -b 132 -d 5F000000 -k '..key)
end
--
-- this second phase reads block two and you're supposed
-- to write back the first two bytes already on the tag
-- plus 0FE0 - for example if the card has 03 48 00 00 in block 2
-- we write back 03480FE0 
local function secondphase(key, twobytes)
    local wholepart = twobytes..'0FE0'
    -- write this out
    core.console('hf mfu wrbl -b 2 -d '..wholepart..' -k '..key)
    -- last bit
    core.console('hf mfu wrbl -b 130 -d 01000FBD -k '..key)
    --print('You must finialize the tag manually, or overight it and then finalize it with:')
    --print('hf mfu wrbl -b 130 -d 01000FBD -k '..key)
    return 'Wrote: '..wholepart
end

-- Check availability of file
function file_check(file_name)
  local file_found=io.open(file_name, "r")      
  
  if file_found==nil then
    file_found=file_name .. " ... Error - File Not Found"
  else
    file_found=file_name .. " ... File Found"
  end
  return file_found
end

--
--- The main entry point
function main(args)

    print( string.rep('--',20) )
    print( string.rep('--',20) )
    print()

    -- Arguments for the script
    for o, a in getopt.getopt(args, 'f:') do
        if o == 'f' then image = a end
        if o == 'h' then print('help') end
    end
    -- output which image
    print('We are making this: '..image)

    print(file_check(image))

    local res, err
    -- read the tag for its UID
    print('Waiting for new tag...')
    res, err = lib14a.waitFor14443a()
    if err then return oops(err) end
    uid = res['uid']
    print('UID is '..uid)

    -- new image filename has the uid in it
    newimage = 'uid_'..uid..'_'..image

    -- calculate the amiibo key
    newkey = get_amiibo_pwd(uid)
    print('Amiibo key is '..newkey)

    -- inject uuid into amiibo image
    injectuid(uid, image, newimage)
    
    -- firstphase
    firstphase(newkey, newimage)
    
    -- read block 2 and grab the first byte
    core.console('hf mfu rdbl -b 2')
    -- ask for the digits
    twobytes = utils.input('What are the first two bytes? XXXX')
    -- secondphase
    print(secondphase(newkey, twobytes))

    print('Done.')
end

main(args)
