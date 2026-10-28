#!/usr/bin/env node
/**
 * check-login.mjs · **登录链路一键排障**（不依赖 App，不依赖 DevEco）
 *
 * 目的：把「一直点登录都提示密码错误」这一个现象，拆成三个可以独立回答的问题 ——
 *   ① 服务端在不在？          → GET /health
 *   ② 账号密码对不对？         → POST /api/auth/login
 *   ③ 拿到的令牌能不能取用户？ → GET /api/auth/me
 *
 * 用法：
 *   node harmony/scripts/check-login.mjs <用户名> <密码> [https://host]
 *
 * 例：
 *   node harmony/scripts/check-login.mjs gzm 123456
 *   node harmony/scripts/check-login.mjs gzm 123456 https://xincell1013.xyz
 *
 * 退出码：
 *   0 = 登录成功  1 = 账号/密码不匹配  2 = 服务端不可达  3 = 其它异常
 *
 * ★ 为什么要有这个脚本：后端对"用户不存在"和"密码错"返回的是**同一个** 401
 *   （`detail=用户名或密码错误`），所以 App 界面上永远看不出是哪一种。
 *   这个脚本额外做了两件 App 里不方便做的事：
 *     · 先探活，明确"服务端到底通不通"，把网络问题和账号问题分开；
 *     · 登录成功后再打一次 `/me`，确认令牌链路（App 登录成功后也会立刻调它）。
 *   如果这里能登录成功而 App 报密码错，问题就在端上（输入框/地址配置）；
 *   如果这里也失败，问题就在账号或服务器本身。
 *
 * ★ 依赖：只用 Node 内置能力（Node 18+ 的全局 fetch），不装任何包。
 * ★ 注意：**不要**用 `process.exit()` 收尾 —— 在 Windows 上它与 undici 的
 *   keep-alive 套接字关闭竞争，会抛 `uv_handle_closing` 断言并把退出码变成 1。
 *   这里统一用 `process.exitCode`，让 Node 自己退出。
 */

const DEFAULT_BASE = 'https://xincell1013.xyz';

function usage() {
  console.log('用法: node harmony/scripts/check-login.mjs <用户名> <密码> [https://host]');
  console.log(`默认服务端: ${DEFAULT_BASE}（与鸿蒙端 ApiConfig 的默认值一致）`);
}

function line(title) {
  console.log(`\n── ${title} ${'─'.repeat(Math.max(0, 58 - title.length))}`);
}

/** 把错误响应读成一行可读文案（后端 detail 可能是字符串，也可能是数组） */
async function readError(res) {
  let text = '';
  try {
    text = await res.text();
  } catch {
    return `HTTP ${res.status}`;
  }
  try {
    const body = JSON.parse(text);
    if (typeof body.detail === 'string') {
      return `HTTP ${res.status} · ${body.detail}`;
    }
    return `HTTP ${res.status} · ${text.slice(0, 300)}`;
  } catch {
    return `HTTP ${res.status} · ${text.slice(0, 300)}`;
  }
}

/** 主流程 · 返回退出码（不直接退出进程） */
async function check(username, password, base) {
  console.log('MindScope · 登录链路排障');
  console.log(`服务端: ${base}`);
  console.log(`用户名: ${username}（长度 ${username.length}）`);
  console.log(`密码  : ${'*'.repeat(password.length)}（长度 ${password.length}）`);

  // ① 探活
  line('① 服务端连通性 GET /health');
  try {
    const res = await fetch(`${base}/health`, { method: 'GET' });
    if (res.ok) {
      const body = await res.json().catch(() => ({}));
      console.log(`✅ 可达 · ${JSON.stringify(body)}`);
    } else {
      console.log(`⚠️  服务端有响应但不是 200：${await readError(res)}`);
    }
  } catch (err) {
    console.log(`❌ 连不上：${err && err.message ? err.message : err}`);
    console.log('   排查：域名解析是否指向当前 FRP 节点？HTTPS 证书是否有效？后端与隧道是否在运行？');
    console.log('   结论：这是**网络或地址**问题，不是密码问题。');
    return 2;
  }

  // ② 登录
  line('② POST /api/auth/login');
  let token = '';
  try {
    const res = await fetch(`${base}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });
    if (!res.ok) {
      const message = await readError(res);
      console.log(`❌ 登录失败 · ${message}`);
      if (res.status === 401) {
        console.log('   服务端**已经回应**了，只是这对账号密码不匹配。可能原因：');
        console.log('   a) 密码输错（注意大小写 / 全角半角 / 手机输入法自动补的空格）；');
        console.log('   b) 用户名不是这个（后端用户名精确匹配、区分大小写）；');
        console.log(`   c) 这个账号不在当前服务器上（现在连的是 ${base}，`);
        console.log('      账号可能注册在另一台后端 / 另一份 depression.db 里）。');
        console.log('   建议：确认注册时用的是哪台服务器，再用同一台重试。');
      } else if (res.status === 403) {
        console.log('   账号被禁用（users.is_active = 0）。');
      }
      return 1;
    }
    const body = await res.json();
    token = body.access_token || '';
    console.log(`✅ 登录成功 · token 长度 ${token.length}`);
  } catch (err) {
    console.log(`❌ 请求异常：${err && err.message ? err.message : err}`);
    return 3;
  }

  // ③ 令牌链路
  line('③ GET /api/auth/me（App 登录成功后立刻会调它）');
  try {
    const res = await fetch(`${base}/api/auth/me`, {
      method: 'GET',
      headers: { Authorization: `Bearer ${token}` }
    });
    if (res.ok) {
      console.log(`✅ ${JSON.stringify(await res.json())}`);
    } else {
      console.log(`❌ ${await readError(res)}`);
    }
  } catch (err) {
    console.log(`❌ 请求异常：${err && err.message ? err.message : err}`);
  }

  line('结论');
  console.log('服务端匹配逻辑正常，登录链路可用。');
  console.log('若 App 仍提示密码错误，请核对 App 登录页底部显示的服务端地址是否与本脚本一致。');
  return 0;
}

async function main() {
  const [, , username, password, baseArg] = process.argv;
  if (!username || !password) {
    usage();
    process.exitCode = 3;
    return;
  }
  const base = (baseArg || DEFAULT_BASE).replace(/\/+$/, '');
  process.exitCode = await check(username, password, base);
}

main().catch((err) => {
  console.error('脚本异常：', err);
  process.exitCode = 3;
});
