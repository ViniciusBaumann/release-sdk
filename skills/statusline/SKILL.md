---
name: statusline
description: >
  Barra de status do Claude Code para projetos release-sdk: modelo + effort, projeto, branch, fase/
  stage/task em andamento (lido de .release-planning/), barra de contexto colorida com tokens, custo e
  duração da sessão, limites 5h/7d e cache hit. Instala/atualiza/remove o `statusLine` em
  ~/.claude/settings.json apontando para uma cópia estável de bin/release-statusline.js.
  Use quando: o usuário quiser a "barra de contexto da sessão" (como a do GSD), ver quanto contexto
  resta sem perguntar, ou personalizar a UI do Claude Code. Claude Code only — sem efeito no Codex.
---

# /release:statusline — barra de status do release-sdk

```text
/release:statusline            # instala ou atualiza (padrão: 2 linhas, com cor)
/release:statusline --lines 1  # uma linha só
/release:statusline --off      # remove o statusLine do settings.json (restaura a barra padrão)
/release:statusline --status   # mostra o que está configurado e testa o script com JSON de exemplo
```

Só Claude Code: sob Codex (`PLUGIN_DATA` definido / sem `CLAUDE_PLUGIN_ROOT`) imprima
"statusline: apenas Claude Code" e encerre sem tocar em nada.

## O que aparece

```text
◆ Opus · high  ▸ hubus  ⎇ feat/134-migracao-easybus  ⟡ fase 134 execute T06 6/9 · Veículo de apoio…
ctx [██████████░░░░░░░░░░] 48% 96k/200k · $1.23 · 1h12m · 5h 23% · 7d 41% · cache 91%
```

O segmento `⟡` lê o `.release-planning/` do projeto atual: o `.progress.json` mais recente de
`phases/` (≤24h) → `fase NN stage TXX feitas/total · nota`; senão o cursor de `STATE.md`; e
`quick <branch>` quando `.unit-active` existe. Cor da barra: verde <60%, amarelo <80%, vermelho ≥80%.

## Instalar / atualizar (padrão)

1. Resolver o plugin: `PLUGIN_DIR="${CLAUDE_PLUGIN_ROOT:-$(ls -d ~/.claude/plugins/cache/release-sdk/release/*/ 2>/dev/null | tail -1)}"`.
   Sem `bin/release-statusline.js` aí: informe e pare.
2. Copiar para um caminho estável, porque o cache do plugin muda de pasta a cada atualização:
   `install -m 0755 "$PLUGIN_DIR/bin/release-statusline.js" ~/.claude/release-statusline.js`.
3. Mesclar em `~/.claude/settings.json` sem perder as outras chaves (backup primeiro):
   ```bash
   cp ~/.claude/settings.json ~/.claude/settings.json.bak-statusline 2>/dev/null || true
   node -e '
     const fs=require("fs"),p=process.env.HOME+"/.claude/settings.json";
     let j={};try{j=JSON.parse(fs.readFileSync(p,"utf8"))}catch{}
     j.statusLine={type:"command",command:"node ~/.claude/release-statusline.js",padding:0};
     fs.writeFileSync(p,JSON.stringify(j,null,2)+"\n");'
   ```
   Com `--lines 1`, o `command` vira `RELEASE_STATUSLINE_LINES=1 node ~/.claude/release-statusline.js`.
   Nunca reescreva outras chaves (hooks, permissions, model); só `statusLine`.
4. Testar: `echo '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$PWD"'"},"context_window":{"used_percentage":25},"cost":{"total_cost_usd":0.5}}' | node ~/.claude/release-statusline.js`
   e mostrar as linhas ao usuário. A barra aparece no próximo evento da sessão (sem reiniciar).
5. Diga em uma linha que após uma atualização do plugin basta rodar `/release:statusline` de novo
   para copiar a versão nova.

## `--off`

Remova só a chave `statusLine` do `~/.claude/settings.json` (mesmo padrão node de merge, `delete
j.statusLine`) e apague `~/.claude/release-statusline.js`. Não toque no backup nem em outras chaves.

## `--status`

Imprima a chave `statusLine` atual (ou "não configurada"), se `~/.claude/release-statusline.js`
existe e se difere de `$PLUGIN_DIR/bin/release-statusline.js` (`cmp -s`), e rode o teste do passo 4.
