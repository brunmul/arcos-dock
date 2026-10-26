# Passation

(Fichier créé le 2026-10-26 : il n'existait pas dans ~/code/docky ; l'archive ~/Documents/Docky est introuvable aussi.)

## Journal

- 2026-10-26 — Icônes des épinglés : le pack Claude (84 icônes au trait) est remplacé par le pack Notion (884 icônes de pages + 49 d'interface, glyphes pleins), embarqué dans Docky/IconPacks/notion-icons.json et chargé par NotionIconPack.swift. Menu « Icon » : Default, puis un sous-menu par lettre (A–Y, 0–9), puis « Interface ». Une icône Claude choisie avant et absente de Notion (ex. « desktop » sur Parsec) est ignorée : l'épinglé retrouve sa propre icône. Testé : compilation, les 933 SVG lisibles par NSImage, rendu de tuiles hors app en clair/sombre. Pas testé à l'écran dans l'app (accès computer-use refusé).
