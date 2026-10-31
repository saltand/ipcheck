import SCRIPT from '../ipsplit.sh';
import PAGE from './page.html';

const CLI_UA = /\b(curl|wget|httpie|powershell|libwww|python-requests|go-http-client|aria2|fetch)\b/i;

function helpText(origin) {
  return `curl -fsSL ${origin}/sh | bash

# with options
curl -fsSL ${origin}/sh | bash -s -- --group ai

# npm
npx @saltand/ipcheck
`;
}

function pageHtml(origin) {
  return PAGE.replaceAll('__ORIGIN__', origin);
}

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const origin = (url.hostname === 'localhost' || url.hostname === '127.0.0.1')
      ? url.origin
      : `https://${url.host}`;
    const text = (body, status = 200) => new Response(body, {
      status,
      headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'public, max-age=300' },
    });
    if (request.method !== 'GET' && request.method !== 'HEAD') return text('Method Not Allowed\n', 405);

    if (url.pathname === '/sh' || url.pathname === '/ipsplit.sh') return text(SCRIPT);
    if (url.pathname === '/') {
      const ua = request.headers.get('user-agent') || '';
      const accept = request.headers.get('accept') || '';
      if (CLI_UA.test(ua) || !accept.includes('text/html')) return text(helpText(origin));
      return new Response(pageHtml(origin), {
        headers: {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'public, max-age=60',
          vary: 'User-Agent, Accept',
        },
      });
    }
    return text(`404 Not Found: ${url.pathname}\nTry: curl -fsSL ${origin}/sh | bash\n`, 404);
  },
};
