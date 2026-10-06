/* Zago Auto Service — Service Worker
 *
 * Objetivo: o app abrir mesmo sem internet (tela inicial) e instalar como PWA.
 * Regras de SEGURANÇA:
 *   - só mexe em requisições do MESMO domínio e do tipo GET;
 *   - NUNCA guarda em cache nada do Supabase (login, tokens, dados) nem de CDN;
 *   - HTML: rede primeiro (você sempre recebe a versão nova); cache só como reserva.
 *
 * Para publicar uma nova versão do app, mude VERSAO abaixo.
 */
const VERSAO = 'zago-v2.6.0';
const ARQUIVOS = ['./', './index.html', './manifest.json', './icon-192.png', './icon-512.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(VERSAO)
      .then((c) => c.addAll(ARQUIVOS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((nomes) => Promise.all(nomes.filter((n) => n !== VERSAO).map((n) => caches.delete(n))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;      // Supabase, CDNs, Google: passa direto

  // Páginas: rede primeiro, cache como reserva (offline)
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then((res) => {
          if (res.ok) { const copia = res.clone(); caches.open(VERSAO).then((c) => c.put('./index.html', copia)); }
          return res;
        })
        .catch(() => caches.match('./index.html'))
    );
    return;
  }

  // Imagens/manifest/ícones: cache primeiro, atualiza em segundo plano
  e.respondWith(
    caches.match(req).then((emCache) => {
      const rede = fetch(req).then((res) => {
        if (res.ok) { const copia = res.clone(); caches.open(VERSAO).then((c) => c.put(req, copia)); }
        return res;
      }).catch(() => emCache);
      return emCache || rede;
    })
  );
});
