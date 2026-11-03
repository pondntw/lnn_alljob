fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lnn_alljob'
description 'All Job (โซนฟาร์มอัตโนมัติตั้งด้วย config) + Ranking ทุกงานแบบ realtime'
version '1.0.0'

dependencies { 'es_extended', 'oxmysql', 'ox_lib' }

-- config ระบุทีละไฟล์ (ไม่ใช้ glob) — functions_server ต้องอยู่ฝั่ง server เท่านั้น
shared_scripts {
    '@ox_lib/init.lua',
    'config/general.lua',
    'config/defaults.lua',
    'config/jobs.lua',
    'config/ranking.lua',
    'config/locale.lua',
    'shared/jobs.lua',
}

-- '@es_extended/imports.lua' ใส่เฉพาะฝั่ง server — client ไม่ใช้ ESX เลย (แจ้งเตือน/เมนูใช้ ox_lib + NUI ของตัวเอง)
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    '@es_extended/imports.lua',
    'config/functions_server.lua',
    'server/board.lua',
    'server/store.lua',
    'server/ranking.lua',
    'server/players.lua',
    'server/jobs.lua',
    'server/main.lua',
}

client_scripts {
    'config/functions_client.lua',
    'client/props.lua',
    'client/jobs.lua',
    'client/ranking.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/hud.css',
    'html/app.js',
    'html/hud.js',
}
