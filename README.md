# Arcos Dock

*[English below](#english)*

**Arcos Dock** remplace le Dock de macOS par une barre latérale, inspirée de trois apps : **Arc** et **Dia** pour la barre qui mêle apps et onglets, et **Slack** pour les thèmes de couleur et la lecture rapide de ce qui demande votre attention. C'est un fork de [Docky](https://github.com/josejuanqm/docky) de José Juan Quintero, publié sous la même licence GPLv3.

## Fonctions clés

- **Une barre encastrée, jamais flottante.** Elle est opaque et collée au bord gauche de l'écran. Les fenêtres sont repoussées, donc aucune ne passe derrière.
- **Apps et onglets au même endroit, comme dans Arc et Dia.** Les onglets ouverts de Chrome ou de Dia s'affichent à côté des apps. Vous pouvez épingler un site comme une app, et une pastille montre ses non-lus (Gmail, Slack…).
- **New Window et New Tab.** Une seule barre de recherche ouvre une app, un onglet déjà ouvert, un favori, une adresse ou une recherche web.
- **Des apps épinglées et des dossiers en tuiles.** Les dossiers ressemblent aux projets Claude, avec un symbole en contour sur une couleur sourde. Les apps ouvertes se déplient pour montrer leurs fenêtres.
- **Des widgets compacts, avec le détail au survol :**
  - le calendrier : les prochains événements, un bouton Rejoindre la visio, et des réponses Oui / Peut-être / Non aux invitations ;
  - les stats du Mac (processeur, mémoire, GPU, disque, réseau) ;
  - le morceau en cours ;
  - la météo ;
  - l'activité de Claude Code.
- **Des thèmes façon Slack**, à côté du thème clair et chaud par défaut. Le fond d'écran peut prendre les couleurs du thème.
- **Des icônes cohérentes.** Arcos Dock cherche d'abord votre pack d'icônes, puis le favicon du site de l'app, puis un symbole coloré tiré de l'icône, et à défaut l'icône d'origine.
- **Trois dispositions :** la barre complète, un rail d'icônes seules, ou une barre en bas de l'écran.

Le dock d'origine de Docky reste disponible : menu « … » → Switch to Dock.

## Installer

1. Téléchargez `Arcos-Dock.zip` depuis la page [Releases](../../releases), puis décompressez-le.
2. Glissez l'app dans le dossier Applications.
3. L'app n'est pas signée par un développeur Apple, donc macOS la bloque au premier lancement. Pour l'ouvrir quand même, au choix :
   - faites un clic droit sur l'app → **Ouvrir**, puis cliquez sur **Ouvrir** dans l'avertissement ;
   - si macOS refuse encore, ouvrez **Réglages Système → Confidentialité et sécurité**, descendez tout en bas et cliquez sur **Ouvrir quand même** ;
   - dans le Terminal, lancez `xattr -dr com.apple.quarantine "/Applications/Arcos Dock.app"`.

Il faut macOS 14 ou plus récent. L'app tourne sur Apple Silicon comme sur Intel.

Arcos Dock garde l'identifiant de Docky (`gt.quintero.Docky`), donc n'installez pas les deux en même temps.

## Permissions demandées

macOS les demande au moment où une fonction en a besoin. Si vous en refusez une, seule cette fonction s'arrête.

| Permission | Pourquoi |
|---|---|
| Accessibilité | Lister et activer les fenêtres, et les tenir hors de la barre. Indispensable. |
| Automatisation (Chrome, Dia, Finder, System Events) | Lire les onglets et passer de l'un à l'autre, ouvrir des pages, agir sur les fichiers et les menus. |
| Calendrier | Afficher les prochains événements et répondre aux invitations. |
| Rappels | Faire marcher le widget Rappels. |
| Localisation | Afficher la météo locale. |

Si l'Accessibilité semble perdue après une mise à jour : retirez l'app de la liste dans Réglages Système → Confidentialité et sécurité → Accessibilité, puis ajoutez-la de nouveau.

## Compiler soi-même

Ouvrez `Docky.xcodeproj` dans Xcode, choisissez le schéma **Docky**, puis cliquez sur Run. Les détails du projet d'origine sont dans [README.upstream.md](README.upstream.md).

## Crédits et licence

- Projet d'origine : [Docky](https://github.com/josejuanqm/docky) par José Juan Quintero, sous GPLv3. Pour le Docky officiel, signé et maintenu, allez sur [getdocky.com](https://getdocky.com).
- Arcos Dock n'est affilié ni au projet d'origine, ni à The Browser Company (Arc, Dia), ni à Slack, ni à Anthropic.
- Licence : [GPLv3](LICENSE), comme le projet d'origine.

---

<a id="english"></a>

# Arcos Dock (English)

**Arcos Dock** replaces the macOS Dock with a sidebar inspired by three apps: **Arc** and **Dia** for a bar that mixes apps and tabs, and **Slack** for its color themes and for showing at a glance what needs your attention. It is a fork of [Docky](https://github.com/josejuanqm/docky) by José Juan Quintero, released under the same GPLv3 license.

## Key features

- **A bar set into the screen edge, never floating.** It is opaque and sits flush against the left edge. Windows are pushed aside, so none ever sits behind it.
- **Apps and tabs in one place, as in Arc and Dia.** Open tabs from Chrome or Dia appear next to your apps. You can pin a site like an app, and a badge shows its unread count (Gmail, Slack…).
- **New Window and New Tab.** One search field opens an app, an open tab, a bookmark, an address or a web search.
- **Pinned apps and folders as tiles.** Folders look like Claude projects, with an outlined symbol on a muted color. Open apps expand to show their windows.
- **Compact widgets, with details on hover:**
  - calendar: upcoming events, a Join button for video calls, and Yes / Maybe / No replies to invitations;
  - Mac stats (CPU, memory, GPU, disk, network);
  - now playing;
  - weather;
  - Claude Code activity.
- **Slack-like themes**, next to the warm default theme. The desktop picture can follow the theme's colors.
- **Consistent icons.** Arcos Dock looks first in your icon pack, then for the app's website icon, then for a colored symbol taken from the icon, and falls back to the original icon.
- **Three layouts:** the full sidebar, an icons-only rail, or a bar along the bottom of the screen.

Docky's original dock is still there: … menu → Switch to Dock.

## Install

1. Download `Arcos-Dock.zip` from the [Releases](../../releases) page and unzip it.
2. Drag the app into Applications.
3. The app is not signed with an Apple developer certificate, so macOS blocks it on first launch. To open it anyway, use one of these:
   - right-click the app → **Open**, then click **Open** in the warning;
   - if macOS still refuses, open **System Settings → Privacy & Security**, scroll to the bottom and click **Open Anyway**;
   - in Terminal, run `xattr -dr com.apple.quarantine "/Applications/Arcos Dock.app"`.

It needs macOS 14 or later, and runs on both Apple Silicon and Intel.

Arcos Dock keeps Docky's identifier (`gt.quintero.Docky`), so do not install both at once.

## Permissions

macOS asks for each one when a feature needs it. If you refuse one, only that feature stops working.

| Permission | Why |
|---|---|
| Accessibility | List and activate windows, and keep them clear of the bar. Required. |
| Automation (Chrome, Dia, Finder, System Events) | Read tabs and switch between them, open pages, act on files and menus. |
| Calendar | Show upcoming events and reply to invitations. |
| Reminders | Run the Reminders widget. |
| Location | Show local weather. |

## Build from source

Open `Docky.xcodeproj` in Xcode, choose the **Docky** scheme, then click Run. The original project's details are in [README.upstream.md](README.upstream.md).

## Credits and license

- Original project: [Docky](https://github.com/josejuanqm/docky) by José Juan Quintero, GPLv3. For the official, signed and maintained Docky, go to [getdocky.com](https://getdocky.com).
- Arcos Dock is not affiliated with the original project, The Browser Company (Arc, Dia), Slack or Anthropic.
- License: [GPLv3](LICENSE), same as the original project.
