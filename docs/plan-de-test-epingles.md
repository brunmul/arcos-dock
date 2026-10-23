# Plan de test : épinglés, listes et menus clic droit

Version testée : branche `perso`, après le commit « fix(sidebar): right-click menus… ».
À faire dans la barre complète (à gauche), puis les points marqués **[R]** en mode icônes seules et **[B]** dans la barre du bas.

Pour chaque test, note **OK** ou ce que tu vois. Si un test rate, fais une capture : la barre et le menu ouvert.

## Préparation

- Avoir 2 apps épinglées **ouvertes** (par exemple Notes et Slack) et 1 app épinglée **fermée**.
- Avoir 1 app **ouverte non épinglée** (par exemple Calculatrice).
- Avoir 1 site épinglé **avec un onglet ouvert** dans Chrome et 1 site épinglé **sans onglet**.
- Avoir au moins 2 widgets en bas.
- Réglages → Sidebar → Content : « Pinned Items Also in Apps & Web » **désactivé** pour la série A, puis **activé** pour la série B.

## Série A : « Pinned Items Also in Apps & Web » désactivé

| # | Action | Attendu |
|---|---|---|
| A1 | Regarder la liste Apps | Les apps épinglées ouvertes n'y sont **pas**. Calculatrice y est. |
| A2 | Clic droit sur la tuile d'une app épinglée **ouverte** | Le menu s'ouvre **sur cette app** (son nom, ses fenêtres). Il contient **Unpin**, **Move to Bottom** et **Quit**. Dans Options, **Keep in Dock est coché**. |
| A3 | Choisir **Quit** dans ce menu | L'app se ferme. Sa tuile reste en place mais grisée. |
| A4 | Clic droit sur la tuile d'une app épinglée **fermée** | Il y a **Unpin**, mais pas **Quit**. |
| A5 | Clic droit sur l'app épinglée ouverte → **Unpin** | La tuile disparaît du haut et l'app **apparaît aussitôt dans la liste Apps**. |
| A6 | Clic droit sur Calculatrice dans la liste → **Pin** | Elle disparaît de la liste et apparaît **en haut** comme tuile. |
| A7 | Clic droit sur le site épinglé **avec onglet** | Il y a **Open in New Tab**, **Unpin**, **Move to Bottom** et **Close Tab** (ou « Close N Tabs » s'il y en a plusieurs). |
| A8 | Choisir **Close Tab** | L'onglet se ferme dans Chrome. La tuile du site reste, grisée. Il ne revient pas après 2 secondes. |
| A9 | Clic droit sur le site épinglé **sans onglet** | Il n'y a pas de Close Tab. |
| A10 | Site avec onglet → **Unpin** | La tuile disparaît et l'onglet **apparaît dans la liste Web**. |
| A11 | Dans la liste Web, clic droit sur cet onglet → **Pin** | L'onglet sort de la liste Web et le site revient en tuile **en haut**. |

## Série B : « Pinned Items Also in Apps & Web » activé

| # | Action | Attendu |
|---|---|---|
| B1 | Regarder Apps et Web | Les apps épinglées ouvertes et les onglets des sites épinglés y sont **aussi**, en plus des tuiles. |
| B2 | Clic droit sur une app épinglée **dans la liste** | Même menu qu'en A2, avec **Unpin** et **Quit**. |
| B3 | **Unpin** depuis la liste | La tuile disparaît en haut et la ligne **reste** dans la liste. |
| B4 | **Pin** depuis la liste | La tuile revient en haut et la ligne **reste** dans la liste. |

## Série C : haut et bas

| # | Action | Attendu |
|---|---|---|
| C1 | App épinglée → **Move to Bottom** | Elle passe en bas avec les widgets, dans la disposition choisie pour le bas. Son menu propose maintenant **Move to Top**. |
| C2 | App en bas → **Unpin**, puis **Pin** depuis la liste Apps | Elle revient **en haut**, pas en bas. |
| C3 | Widget → **Move to Top** | Il passe en haut, avec les épinglés. |
| C4 | Widget → **Remove** | Il disparaît. Réglages → Sidebar → Widgets : son interrupteur est éteint. Le rallumer le fait revenir **à sa place**. |
| C5 | Réglages → Content → Haut en **List** | Les épinglés du haut passent en lignes (icône et nom). Le clic droit marche sur chaque ligne comme sur les tuiles. |
| C6 | Bas en **Grid** | Les widgets du bas deviennent des tuiles. Au survol, le détail s'ouvre. Le clic droit propose Move to Top et Remove. |

## Série D : bon élément sous la souris

Ces tests visent les menus qui s'ouvraient sur un autre élément que celui cliqué.

| # | Action | Attendu |
|---|---|---|
| D1 | Avoir assez d'apps et d'onglets pour que la liste défile. La faire défiler à mi-hauteur. | — |
| D2 | Clic droit sur chaque widget du bas | Le menu est **celui du widget** (Move to Top et Remove), jamais celui d'une app ou d'un onglet caché derrière. |
| D3 | Clic droit sur la première ligne visible de la liste, juste sous l'en-tête | Le menu est celui **de cette ligne**. |
| D4 | Refaire D2 et D3 avec la liste défilée tout en bas, puis tout en haut | Même résultat. |

## Série E : formes réduites

| # | Action | Attendu |
|---|---|---|
| E1 **[R]** | Mode icônes seules : clic droit sur une app épinglée ouverte | **Unpin** et **Quit** sont présents. |
| E2 **[R]** | Clic droit sur un site épinglé avec onglet | **Close Tab** est présent. |
| E3 **[B]** | Barre du bas : mêmes tests que E1 et E2 | Même résultat. |
| E4 **[R][B]** | Unpin depuis ces formes | L'élément rejoint la liste des apps ou des onglets ouverts de cette forme. |

## Ce qui a été corrigé avant ce plan

- **Keep in Dock** apparaissait décoché sur une app épinglée. Le menu ne savait pas que l'app était épinglée, donc le cocher ne faisait rien. Corrigé.
- Le clic droit pouvait être pris par un élément **caché** : une ligne sortie de la liste en défilant, ou passée sous les widgets. Le menu s'ouvrait alors sur un autre élément, et Unpin pouvait toucher la mauvaise app. Corrigé : seule la partie visible d'un élément reçoit le clic droit.
- Un site épinglé n'avait aucun moyen de **fermer** son onglet au clic droit. **Close Tab** a été ajouté.
- Une app désépinglée gardait sa place « en bas ». Une fois réépinglée, elle revenait en bas. Elle revient maintenant en haut.
