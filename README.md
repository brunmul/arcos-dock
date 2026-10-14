# Docky Sidebar

*[English below](#english)*

Une barre latérale pour macOS, façon Arc / Dia, avec un look inspiré de Claude. C'est un fork personnel de [Docky](https://github.com/josejuanqm/docky) de José Juan Quintero, publié sous la même licence GPLv3.

## Ce que c'est

Au lieu d'un dock en bas de l'écran, Docky Sidebar pose une barre encastrée le long du bord gauche :

- les apps épinglées et les dossiers en tuiles en haut ;
- les apps ouvertes en lignes, qui se déplient sur leurs fenêtres ;
- les onglets du navigateur (Chrome ou Dia) mêlés aux apps, et des sites épinglés ;
- « New Window » et « New Tab » ouvrent une recherche d'apps, d'onglets, de favoris ou du web ;
- des widgets compacts en bas (calendrier avec bouton Rejoindre et réponses aux invitations, stats du Mac, média en cours, météo, activité de Claude Code), avec le détail au survol ;
- un mode rail (icônes seules), une variante en barre du bas, et des thèmes de couleur ;
- les fenêtres sont repoussées pour ne jamais passer derrière la barre.

Le dock d'origine de Docky reste disponible (menu « … » → Switch to Dock).

## Installer

1. Téléchargez `Docky-Sidebar.zip` dans la page [Releases](../../releases) et décompressez-le.
2. Glissez `Docky.app` dans le dossier Applications.
3. L'app n'est pas signée par un développeur Apple, donc macOS la bloque au premier lancement. Pour l'ouvrir quand même :
   - faites un clic droit sur `Docky.app` → **Ouvrir**, puis **Ouvrir** dans la fenêtre d'avertissement ;
   - si macOS refuse encore, allez dans **Réglages Système → Confidentialité et sécurité**, tout en bas, et cliquez sur **Ouvrir quand même** ;
   - ou, dans le Terminal : `xattr -dr com.apple.quarantine /Applications/Docky.app`.

macOS 14 ou plus récent. Build universel (Apple Silicon et Intel).

Attention : cette app utilise le même identifiant que Docky (`gt.quintero.Docky`). N'installez pas les deux en même temps.

## Permissions demandées

macOS vous les demandera au fur et à mesure ; vous pouvez en refuser certaines, seules les fonctions concernées s'arrêtent.

| Permission | Pourquoi |
|---|---|
| Accessibilité | Lister et activer les fenêtres, et les repousser hors de la barre. Indispensable. |
| Automatisation (Chrome, Dia, Finder, System Events) | Lire et changer d'onglet, ouvrir des pages, actions sur les fichiers et les menus. |
| Calendrier | Widget calendrier : prochains événements et réponses aux invitations. |
| Rappels | Widget rappels. |
| Localisation | Météo locale. |

Si l'Accessibilité semble perdue après une mise à jour : retirez Docky de la liste dans Réglages Système → Confidentialité et sécurité → Accessibilité, puis rajoutez-le.

## Compiler soi-même

Ouvrez `Docky.xcodeproj` dans Xcode, schéma **Docky**, puis Run. Voir [README.upstream.md](README.upstream.md) pour les détails du projet d'origine.

## Crédits et licence

- Projet d'origine : [Docky](https://github.com/josejuanqm/docky) par José Juan Quintero, sous GPLv3. Si vous voulez le vrai Docky, signé et à jour : [getdocky.com](https://getdocky.com).
- Ce fork n'est pas affilié au projet d'origine, ni à Anthropic, Arc ou Dia.
- Licence : [GPLv3](LICENSE), comme le projet d'origine.

---

<a id="english"></a>

# Docky Sidebar (English)

A macOS sidebar in the manner of Arc / Dia, with a Claude-inspired look. It is a personal fork of [Docky](https://github.com/josejuanqm/docky) by José Juan Quintero, released under the same GPLv3 license.

## What it is

Instead of a dock along the bottom, Docky Sidebar sets a bar into the left edge of the screen:

- pinned apps and folders as tiles at the top;
- open apps as rows that expand into their windows;
- browser tabs (Chrome or Dia) listed with the apps, and pinned sites;
- "New Window" and "New Tab" open a search across apps, tabs, bookmarks and the web;
- compact widgets at the bottom (calendar with Join button and invitation replies, Mac stats, now playing, weather, Claude Code activity), with details on hover;
- a compact rail (icons only), a bottom-bar variant, and color themes;
- windows are pushed aside so nothing ever sits behind the bar.

Docky's original dock is still there (… menu → Switch to Dock).

## Install

1. Download `Docky-Sidebar.zip` from [Releases](../../releases) and unzip it.
2. Drag `Docky.app` into Applications.
3. The app is not signed with an Apple developer certificate, so macOS blocks it on first launch. To open it anyway:
   - right-click `Docky.app` → **Open**, then **Open** in the warning;
   - if macOS still refuses, go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**;
   - or in Terminal: `xattr -dr com.apple.quarantine /Applications/Docky.app`.

Requires macOS 14 or later. Universal build (Apple Silicon and Intel).

Note: the app uses the same identifier as Docky (`gt.quintero.Docky`). Do not install both at once.

## Permissions

macOS asks for these as features need them; refusing one only turns off what depends on it.

| Permission | Why |
|---|---|
| Accessibility | List and activate windows, and keep them clear of the bar. Required. |
| Automation (Chrome, Dia, Finder, System Events) | Read and switch tabs, open pages, file and menu actions. |
| Calendar | Calendar widget: next events and invitation replies. |
| Reminders | Reminders widget. |
| Location | Local weather. |

## Build from source

Open `Docky.xcodeproj` in Xcode, scheme **Docky**, then Run. See [README.upstream.md](README.upstream.md) for the original project's details.

## Credits and license

- Original project: [Docky](https://github.com/josejuanqm/docky) by José Juan Quintero, GPLv3. For the real, signed and maintained Docky: [getdocky.com](https://getdocky.com).
- This fork is not affiliated with the original project, nor with Anthropic, Arc or Dia.
- License: [GPLv3](LICENSE), same as the original project.
