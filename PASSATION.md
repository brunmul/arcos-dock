# Passation

(Fichier créé le 2026-10-26 : il n'existait pas dans ~/code/docky ; l'archive ~/Documents/Docky est introuvable aussi.)

## Journal

- 2026-10-26 — Icônes des épinglés : le pack Claude (84 icônes au trait) est remplacé par le pack Notion (884 icônes de pages + 49 d'interface, glyphes pleins), embarqué dans Docky/IconPacks/notion-icons.json et chargé par NotionIconPack.swift. Menu « Icon » : Default, puis un sous-menu par lettre (A–Y, 0–9), puis « Interface ». Une icône Claude choisie avant et absente de Notion (ex. « desktop » sur Parsec) est ignorée : l'épinglé retrouve sa propre icône. Testé : compilation, les 933 SVG lisibles par NSImage, rendu de tuiles hors app en clair/sombre. Pas testé à l'écran dans l'app (accès computer-use refusé).
- 2026-10-26 — Icônes Notion des épinglés : plus de tuile à fond doux, le glyphe occupe toute la taille de l'icône. Il est coloré d'après le thème, avec la même règle que Palette.IconColor sur Windows (hash FNV-1a du nom ; encres sourdes des dossiers sans le gris pour le thème Claude et les thèmes presque sans couleur ; sinon six teintes à 60° depuis l'extrémité la plus saturée du dégradé, S 55 %, L 40 % en clair / 72 % en sombre), dans la barre et dans le menu Icon. Testé : compilation, relance. Pas testé à l'écran (accès computer-use refusé).
