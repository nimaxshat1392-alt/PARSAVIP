const List<String> defaultConfigUris = [
  // ═══ VLESS Reality (کیفیت بالا) ═══
  'vless://c5694dc5-39fd-4a92-8430-3837baa522a3@212.46.33.5:443?type=tcp&security=reality&flow=xtls-rprx-vision&fp=firefox&pbk=z37XIezsPyfMgmdXyFd9qT4C4maDAs1OcRt-wfyrXVo&sid=9c2378562188c3cb&sni=slowkd.sadiepinki.com',
  'vless://e2b8b217-cffb-4d66-9b8b-eca6e4334032@13.231.19.51:11690?security=reality&encryption=none&pbk=Bv3z0_uFRabB9C4CFpNfqepZUyeO4YTh1duJdMBNLkg&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=www.tesla.com&sid=034885e346fd30',
  'vless://48ff2b70-e180-582f-8866-d9a2edeed5f5@ww13.levikogjgfdd.ir:23576?security=reality&type=tcp&sni=fuck.rkn&fp=chrome&flow=xtls-rprx-vision&sid=01&pbk=1y5h2FGWKXTJ9xLPCqPo6Mw7RxoZzh6fGkEQKNxpZ3s&encryption=none',
  'vless://48ff2b70-e180-582f-8866-d9a2edeed5f5@15.204.97.197:23576?security=reality&type=raw&sni=fuck.rkn&fp=chrome&flow=xtls-rprx-vision&sid=01&pbk=1y5h2FGWKXTJ9xLPCqPo6Mw7RxoZzh6fGkEQKNxpZ3s&encryption=none',
  'vless://ac0c2945-b758-11f1-8181-54db13ea7d40@31.76.249.44:443?encryption=none&type=tcp&flow=xtls-rprx-vision&security=reality&sni=www.akamai.com&pbk=gydLdekl4sNcE2j7vueKJJhpYWTBxlGs_VQ6-ZH55iQ&allowInsecure=1&fp=chrome',
  'vless://71091100-c6ed-41fa-84ac-acf7ff9eeb7f@212.46.33.5:443?encryption=none&flow=xtls-rprx-vision&fp=&pbk=z37XIezsPyfMgmdXyFd9qT4C4maDAs1OcRt-wfyrXVo&security=reality&sid=9c2378562188c3cb&sni=slowkd.sadiepinki.com&type=tcp',
  'vless://d65cc14c-f53f-4fe2-b262-97856601319c@169.40.42.35:443?encryption=none&flow=xtls-rprx-vision&fp=&pbk=e2RLf57Li_-MDZGE9ss1BWPgP54mqRb5PfXhW2jcVVg&security=reality&sid=c39cc7310a&sni=yahoo.com&type=tcp',
  'vless://d65cc14c-f53f-4fe2-b262-97856601319c@169.40.42.231:443?security=reality&encryption=none&pbk=e2RLf57Li_-MDZGE9ss1BWPgP54mqRb5PfXhW2jcVVg&headerType=none&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=yahoo.com&sid=c39cc7310a',
  'vless://38b8e2fb-b9a0-40a6-b42c-335def2765cf@au1.gsafevpnapi.com:20270?security=reality&type=tcp&sni=www.yahoo.com&fp=chrome&flow=xtls-rprx-vision&sid=e6a5a4a9115456de&pbk=RHLiKldLu3DONcQoX4Kjs7Xmd2K25ndVbw4pwxe45XE',
  'vless://7cde4592-4758-415f-8b97-c188faa4d1c9@188.225.25.142:443?encryption=none&flow=xtls-rprx-vision&fp=firefox&pbk=SxbaWzlvE_HQqqsA4PNX2PFcSYXTVE2nZlgLc7cPOgk&security=reality&sid=8681edc9&sni=prime.betust.net&type=raw',

  // ═══ VLESS + TLS + WS (کیفیت بالا) ═══
  'vless://dc1e9f00-c064-4870-9bfc-463db50257d7@104.21.15.145:2053?encryption=none&security=tls&sni=RESTlESs-MoON-dD68RidaM-tOo-In-MAmLEkat.hGtghFF67tdFHUt3.WORkerS.DEV&alpn=http/1.1&type=ws&host=restless-moon-dd68ridam-too-in-mamlekat.hgtghff67tdfhut3.workers.dev&path=/eyJqdW5rIjoicVkwaG9XUUQyUDhzRkZ5UiIsInByb3RvY29sIjoid2wiLCJtb2RlIjoicHJveHlpcCIsInBhbmVsSVBzIjpbXX0=',
  'vless://36788cf4-fcb4-49c5-a563-5f888849b1cc@104.21.8.201:2096?path=/vqyps6kf3&security=tls&encryption=none&host=cdn-jp.skyvora.app&fp=chrome&type=ws&sni=cdn-jp.skyvora.app',
  'vless://735b8344-0b95-464c-b687-1c5616138908@172.67.130.159:2096?encryption=none&security=tls&sni=cdn-de.skyvora.app&fp=chrome&type=ws&host=cdn-de.skyvora.app&path=/3cagtz3',
  'vless://550d6eb0-1775-44a4-a464-9176e3d74b50@104.21.8.201:2096?security=tls&fp=chrome&sni=cdn-us.skyvora.app&type=ws&headerType=none&host=cdn-us.skyvora.app&path=%2F0i027asku',
  'vless://0b41f339-5809-46ef-8351-b03fdc441539@fpoixf69hqt3e6d4urtb.mamadneizeh.workers.dev:443?security=tls&type=ws&path=/vl/lYNtP7z8pJUmfp01tz5wEnuDujJtZ&packetEncoding=xudp&alpn=http/1.1&sni=FpoiXF69hQT3E6d4URTB.MamADNEIZeH.WorKers.DEV&fp=chrome&encryption=none',
  'vless://90f0ae37-5a8f-4649-98ad-ac5323840f93@104.21.70.21:443?encryption=none&fp=unsafe&host=silent-king-06b6.297-842.workers.dev&path=/pyip%3DProxyIP.SG.CMLiussss.net&security=tls&sni=silent-king-06b6.297-842.workers.dev&type=ws',

  // ═══ VLESS + WS (پورت ۸۰ و ۸۸۸۰) ═══
  'vless://44594ef3-f732-4e88-b4ae-8583ce21e6b8@188.114.97.6:80?security=none&type=ws&path=%2FCooonfigCooonfigCooonfigCooonfigCooonfig&host=msjsi.azazilvpn.sbs.&encryption=none',
  'vless://85e14d59-02ea-4642-a317-50f1e1691660@anydesk.com:8880?type=ws&encryption=none&path=%2Fpyip%3DProxyIP.KR.CMLiussss.net&host=icy-hat-20f3.328-99f.workers.dev&fp=chrome&alpn=http%2F1.1&headerType=none',

  // ═══ VMess ═══
  'vmess://eyJ2IjpudWxsLCJwcyI6IkpQIiwiYWRkIjoiMTY4LjExMC42MC4xMDQiLCJwb3J0IjoxODExMiwiaWQiOiJhZDQ1ZjhmNi0wZjBhLTRjYzQtYjkwNy1jNDU4MjQwN2RjOTQiLCJhaWQiOiIwIiwic2N5IjoiYXV0byIsIm5ldCI6InRjcCIsInR5cGUiOm51bGwsImhvc3QiOiJvYy5pbWZ1bi5mdW4iLCJhbHBuIjpudWxsLCJwYXRoIjoiLyIsInRscyI6Im5vbmUiLCJzbmkiOm51bGwsImZwIjpudWxsfQ==',
  'vmess://eyJhZGQiOiIxNjUuMTU0LjE5NS4zOCIsImFpZCI6IjAiLCJhbHBuIjoiIiwiZnAiOiIiLCJob3N0IjoiIiwiaWQiOiI5NTlhOGNhZi00Y2VhLTQzZDAtYTU0OC0zNjI4ZTdkZGZhZmMiLCJpbnNlY3VyZSI6IjAiLCJuZXQiOiJ0Y3AiLCJwYXRoIjoiIiwicGNzIjoiIiwicG9ydCI6MzUwMzQsInBzIjoiVFciLCJzY3kiOiJhdXRvIiwic25pIjoiIiwidGxzIjoibm9uZSIsInR5cGUiOiJub25lIiwidiI6IjIiLCJ2Y24iOiIifQ==',

  // ═══ Trojan ═══
  'trojan://MITIVpN@167.82.76.7:443?security=tls&alpn=http/1.1&host=mitivpn---ss--s---mitivpn-33e.global.ssl.fastly.net&fp=chrome&type=ws&sni=ssl.fastly.com',

  // ═══ Shadowsocks ═══
  'ss://YWVzLTEyOC1nY206c2hhZG93c29ja3M@156.146.38.169:443',
  'ss://YWVzLTEyOC1nY206c2hhZG93c29ja3M@156.146.38.167:443',
  'ss://MjAyMi1ibGFrZTMtY2hhY2hhMjAtcG9seTEzMDU6QnNMakZGeTg0Z1JDY1I0YnMzWXR4MW5wN29vaUxNbUZGQ2p4azJQNDV0OD0=@130.61.115.100:59924',
];
