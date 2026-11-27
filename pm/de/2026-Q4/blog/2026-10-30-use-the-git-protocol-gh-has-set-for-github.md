<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Neue Repos folgen dem Git-Protokoll, das gh für github.com nutzt

## Motivation

- Nachdem gg_create_repo das Repository auf GitHub angelegt hat, setzt es
  den Remote `origin` und pusht `main`.
- Die Remote-URL soll dazu passen, wie der Nutzer mit GitHub spricht:
  SSH-Nutzer bekommen `git@github.com:<org>/<name>.git`, alle anderen
  `https://github.com/<org>/<name>.git`.
- gg_create_repo las diese Wahl mit `gh config get git_protocol`.
- `gh auth login` speichert das Protokoll aber nicht global, sondern pro
  Host, in `hosts.yml` unter `github.com`.
- Der Aufruf ohne Host sah nur den globalen Default, und der ist `https`.
  SSH-Nutzer bekamen deshalb einen https-Remote und mussten ihn von Hand
  umstellen.

## Strategie

- gh nach dem Protokoll des Hosts fragen, auf dem das Repository liegt.
- Den Rückfall gh überlassen: Ein Host ohne eigene Einstellung antwortet
  mit der globalen.
- Alles andere bleibt: ein gh-Aufruf, `ssh` wählt SSH, jeder andere Wert
  oder ein fehlgeschlagener Aufruf wählt https.

## gh nach dem Host fragen

- `GitHub.cloneUrl` in `lib/src/github.dart` ruft jetzt
  `gh config get git_protocol --host github.com` auf.
- Der einzige Aufrufer, `RepoCreator._push`, bleibt unverändert. Er legt
  `origin` mit der URL an oder aktualisiert ihn und pusht mit Wiederholung.
- Ein Repository, das nach einem gescheiterten Push fortgesetzt wird, bekommt
  seinen Remote neu aus der aktuellen gh-Einstellung.

## Tests

- Der `cloneUrl()`-Test in `test/github_test.dart` prüft jetzt auch die
  genauen gh-Argumente, einschließlich `--host github.com`.
- Er deckt weiterhin beide Ergebnisse ab: `ssh` ergibt die SSH-URL, ein
  fehlgeschlagener gh-Aufruf die https-URL.

## Offene Punkte

- gg_create_repo kennt nur github.com. GitHub-Enterprise-Hosts oder
  `GH_HOST` werden nicht unterstützt, weder für das Protokoll noch für das
  Repository selbst.
