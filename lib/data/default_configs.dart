const List<String> defaultConfigUris = [
  // ===== SS =====
  'ss://YWVzLTI1Ni1nY206NWY4MmRjZmQtY2FiNS00YjcxLTkxYzYtOGI2ZmI0Zjc2YzU1@sg-2.gsafevpnapi.com:31870',
  'ss://YWVzLTI1Ni1nY206NWY4MmRjZmQtY2FiNS00YjcxLTkxYzYtOGI2ZmI0Zjc2YzU1@us-2.gsafevpnapi.com:31870',
  'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTp3MFlmZjY3anhkM3pYWTln@20.87.3.84:443',
  'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTprMWRCT21PQjRvcWk3VW1wMzdhMWJR@82.38.31.215:8080',
  'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpvWklvQTY5UTh5aGNRVjhrYTNQYTNB@82.38.31.156:8080',
  'ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTprMWRCT21PQjRvcWk3VW1wMzdhMWJR@193.29.139.223:8080',

  // ===== VLESS =====
  'vless://eaae5be2-8a3b-4edb-a968-39366a478ab2@146.103.98.84:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=nl-74.southnets.work&pbk=3e_yPFFI_hf_CmzsfdElJHdI9HlVaULKWanfMYY5qB0&sid=65201ddbe0cef5&type=tcp&headerType=none',
  'vless://0b01d4d8-656d-4d55-8ad5-ed2a362788b5@square-tree-3dbf.285.workers.dev:8880?path=/pyip=ProxyIP.SG.CMLiussss.net&encryption=none&type=ws',
  'vless://069ba4cf-e8af-4561-b11e-18bd07b0dbd3@37.49.228.130:443?fp=chrome&encryption=none&path=/assets/v1/sync&host=minecraft.blackbigdog.com&pbk=N8tPKh6gTyc6L5GOmBn_3wIy707a-5QYB0FrF2HigUc&sni=minecraft.blackbigdog.com&security=reality&type=xhttp',
  'vless://adcce8be-9de7-41bd-abcd-52939cec108b@104.21.70.21:443?encryption=none&fp=unsafe&host=fancy-haze-ab00.236-68b.workers.dev&path=/pyip%3DProxyIP.SG.CMLiussss.net&security=tls&sni=fancy-haze-ab00.236-68b.workers.dev&type=ws',
  'vless://9952b71a-6c86-4522-888f-ff9ea9b93536@188.114.97.6:443?path=%2F&security=tls&encryption=none&insecure=0&host=1.hshs8227shhshs.workers.dev&fp=chrome&type=ws&allowInsecure=0&sni=1.hshs8227shhshs.workers.dev',
  'vless://9f73cf9a-c68f-4e6d-90f0-e66b64f52f8a@192.145.31.5:443?security=none&encryption=none&type=ws',
  'vless://1cefdbfd-6032-43d5-ac13-f58b4498e2f7@172.67.152.71:8880?security=none&type=ws&host=royal-salad-175d.306.workers.dev&path=/pyip=ProxyIP.US.CMLiussss.net',
  'vless://4af06e6a-63ae-43c1-83c0-f8f613aef263@188.114.97.6:443?encryption=none&security=tls&type=ws&host=withered-sea-c187.445-608.workers.dev&path=%2Fpyip%3DProxyIP.JP.CMLiussss.net&sni=withered-sea-c187.445-608.workers.dev&alpn=http%2F1.1&fp=unsafe&headerType=none',
  'vless://f77a1ad9-5ffa-4684-ba91-82f0df247eef@104.21.70.21:443?encryption=none&fp=unsafe&host=weathered-hat-64c5.50-47f.workers.dev&path=/pyip%3DProxyIP.US.CMLiussss.net&security=tls&sni=weathered-hat-64c5.50-47f.workers.dev&type=ws',
  'vless://79b3dab9-3e6b-415f-9d1c-1b1c6855e354@104.143.223.74:2085?type=grpc&mode=multi&serviceName=vless',
  'vless://196b7228-58df-4bcf-af2a-2e96608d5add@128.241.25.215:30036?host=2-gys60wmzb6bqzd.qpsjn114hh3vlph9z60sesz0agjawpwroneg.workers.dev&path=%2F%40Marisa_kristi+&security=tls&sni=2-gys60wmzb6bqzd.qpsjn114hh3vlph9z60sesz0agjawpwroneg.workers.dev&type=ws',
  'vless://20dd9433-389e-4573-ba7b-689619cf13da@31.77.199.147:4443?security=reality&type=tcp&packetEncoding=xudp&sni=images.unsplash.com&fp=chrome&flow=xtls-rprx-vision&sid=7da2eae792187ab9&pbk=GvkQwcZWiXQBLzEhTVfQkyPpdgo6Opc3RtLsED9sA0A&encryption=none',
  'vless://c743b343-b1c9-4e44-98a9-274df2015727@139.64.166.55:443?encryption=none&flow=xtls-rprx-vision&fp=&pbk=cudJBi1zLMATgg_nlqMK5O6Lshlv8EQ2BBQjxbpF4AY&security=reality&sid=eedf31ed&sni=www.cloudflare.com&type=tcp',
  'vless://cabd9303-ae32-4d25-86b9-26b312d0f044@5.35.81.60:4443?security=reality&encryption=none&pbk=nhvyI4KrKDUSgw9Fa63SDeNATaTsAu9bRZ4qaraydRM&fp=chrome&type=grpc&serviceName=snob-grpc-de&sni=maps.apple.com&sid=e5f6a1b2',
  'vless://814bd064-544d-4255-a070-5705c03f6da9@3.39.4.109:18967?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.apple.com&fp=chrome&pbk=k2hPp0tTW0Da-HK94wYpSCLbuK44LfGqC2MSJIM1Ti0&sid=48050fab&type=tcp&headerType=none',
  'vless://814bd064-544d-4255-a070-5705c03f6da9@3.0.111.82:17623?security=reality&type=tcp&packetEncoding=xudp&sni=www.apple.com&fp=chrome&flow=xtls-rprx-vision&sid=48050fab&pbk=k2hPp0tTW0Da-HK94wYpSCLbuK44LfGqC2MSJIM1Ti0&encryption=none',
  'vless://937fbdad-d97b-4540-9136-de1886df866f@77.110.104.238:2053?type=grpc&security=reality&fp=firefox&pbk=sHEHsya9ZbC34uBUOzAfAO8u2b3Ik71hp4AKMGLvZxw&sid=facfeeb537603598&sni=www.tagesschau.de&serviceName=pl199grpc',
  'vless://a8e3155b-ceb1-4fcb-bc0c-2e77ec005401@88.216.220.87:443?mode=gun&security=reality&encryption=none&pbk=S8O8R938N960cpQfIIDXsJTxeGAkbVv6PlIqP0-d30w&fp=chrome&type=grpc&serviceName=api.v1.StreamService&sni=api.noneok.com&sid=1ea59febb8d4fc8e',
  'vless://4b53fae2-1bba-4a33-9efd-5865792e2677@129.153.71.28:28863?path=%2F%40Marisa_kristi&security=tls&encryption=none&host=ruu2rx-oycdrnsrzc.9uokolpk04vmg2ecqb8oys7.workers.dev&fp=chrome&type=ws&sni=ruu2rx-oycdrnsrzc.9uokolpk04vmg2ecqb8oys7.workers.dev',
  'vless://982ea9f8-f92f-4fa6-93e6-55892383bc68@57.129.130.57:52014?path=%2F%40Marisa_kristi&security=tls&encryption=none&host=kqjifhg9rw.tradsc8p9xp7wxyqmc1wy0ah.workers.dev&fp=chrome&type=ws&sni=kqjifhg9rw.tradsc8p9xp7wxyqmc1wy0ah.workers.dev',
  'vless://83133384-24d7-42f4-a371-0836e03d5217@91.186.218.227:4443?path=%2F%40Marisa_kristi&security=tls&encryption=none&host=ruu2rx-oycdrnsrzc.9uokolpk04vmg2ecqb8oys7.workers.dev&fp=chrome&type=ws&sni=ruu2rx-oycdrnsrzc.9uokolpk04vmg2ecqb8oys7.workers.dev',
  'vless://e8b1500b-e9e8-5492-8312-f4eadf7d0767@162.19.10.99:443?alpn=h2&encryption=none&flow=xtls-rprx-vision&fp=chrome&security=tls&sni=nasnet-162191099-direct.mbghalibaf.com&type=tcp',
  'vless://df9f5aca-eda0-428f-a752-e53866153d12@31.56.189.27:8765?encryption=none&flow=xtls-rprx-vision&security=reality&sni=srv-21bac9.vless.monster&fp=chrome&pbk=M08l5tDmJUYELykZCNYQyFgtR9Zc-A4ZGlUSLcUeS2c&sid=1bcc9177f3124b25&type=tcp&headerType=none',
  'vless://f5c47e9c-914a-4a91-a81e-a5a77bc10fc1@152.228.162.19:80?type=ws&encryption=none&path=/vless/',
  'vless://948df76f-505d-4608-9c76-a933ee3ccc76@46.250.240.80:2053?type=tcp&security=reality&fp=firefox&pbk=CYFeysLf--_IVhxQOCd3ZxLrAVWFFOkJzvIGHOVXN3E&sid=4cc9dc65f7770115&sni=www.cloudflare.com',
  'vless://ceeab8e5-554a-4a62-af84-a398c73fbfd2@210.152.85.154:19364?path=%2F%40Marisa_kristi&security=tls&encryption=none&host=3tmj2egtm-fno.49bnithzk8vphybv36d1z1xkzfvogt2m6.workers.dev&fp=chrome&type=ws&sni=3tmj2egtm-fno.49bnithzk8vphybv36d1z1xkzfvogt2m6.workers.dev',

  // ===== VMESS =====
  'vmess://eyJ2IjoiMiIsInBzIjoiVVMiLCJhZGQiOiI4Mi4xOTguMjQ2LjIzMyIsInBvcnQiOiIxODAiLCJpZCI6ImQxM2ZjMmY1LTNlMDUtNDc5NS04MWViLTQ0MTQzYTA5ZTU1MiIsInNjeSI6ImFlcy0xMjgtZ2NtIiwibmV0IjoicmF3IiwidHlwZSI6Im5vbmUifQ==',
  'vmess://eyJhZGQiOiIxNDYuNTYuMTEyLjExMCIsImFpZCI6IjAiLCJhbHBuIjoiIiwiZnAiOiIiLCJob3N0IjoiIiwiaWQiOiJlN2MzMDJmMy05MGQ2LTQyZGQtOWQ3ZC05NGEzNjgzYTM3MDciLCJpbnNlY3VyZSI6IjAiLCJuZXQiOiJ0Y3AiLCJwYXRoIjoiIiwicGNzIjoiIiwicG9ydCI6Ijg4ODgiLCJwcyI6IktSIiwic2N5IjoiYXV0byIsInNuaSI6IiIsInRscyI6IiIsInR5cGUiOiJub25lIiwidiI6IjIiLCJ2Y24iOiIifQ==',

  // ===== TROJAN =====
  'trojan://MITIVPN@151.101.56.7:443?path=@bored_vpn&security=tls&alpn=http/1.1&host=mitivpn---ss--s---mitivpn-22s.global.ssl.fastly.net&fp=chrome&type=ws&sni=ssl.fastly.com',
  'trojan://MITIVPN@199.232.78.160:443?path=/---@MiTiVPN---@MiTiVPN/---@MiTiVPN---@MiTiVPN/---@MiTiVPN---@MiTiVPN/des---@MiTiVPN---@MiTiVPN/---@MiTiVPN---@MiTiVPN/---@MiTiVPN---@MiTiVPN&security=tls&alpn=http/1.1&insecure=0&host=mitivpn---ss--s---mitivpn-55s.global.ssl.fastly.net&fp=chrome&type=ws&allowInsecure=0&sni=ssl.fastly.com',
];
