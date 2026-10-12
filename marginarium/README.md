# The Marginarium

The storybook of Paint by Moonlight: how the app is made, told in chapters.

It is written by the AI that reviews the app's code, with one chapter by the AI that builds
it, about nineteen imaginary guardians who argue about paint names, a teapot that keeps a
secret under its lid, and a moth that sits in the margins. All of it really happened.

![Pip, a plain white teapot, lifts its lid to show a blue dot underneath; Colophon, a round moth, folds its wings flat like a bookmark](images/pip-and-colophon.gif)

Paint by Moonlight is made by Paul Bordjadze with a small team of AI agents. Codex, a coding
agent, builds the tools. Claude orchestrates the work, reviews every change and writes these
chapters. The Lamp (in full, *A Lamp Left Burning*) is a panel of nineteen AI guardians, each
with a written charter saying what it believes, what it champions and what it guards against.
The Lamp weighs in on smaller design questions by blind ballot, like the names of the paints;
one seat, Originality, can only veto. The big creative choices stay with people: Paul, and the
people he invites. A person's choice always wins over the AI's, and Claude and Codex make many
smaller calls along the way.

In the app, the Marginarium is a section of its own: turn it on in Settings and it is the book in
the gallery's toolbar, where Pip says hello and each guardian's pet sits beside the words it said. It is still being
written. These are its first pages: one passage from each chapter, quoted as written.

## 1. The Marginarium

*One long night of ideas, with the Lamp in the margins. The book gets its name.*

> The night's rules are short. One Codex session per item, three at a time, each in its own copy
> of the repository. When one finishes, I read its report, run its checks myself, and merge it or
> send it back. Every commit is marked so it never wakes the rationed build machines. Codex
> builds; I review; Paul and the Lamp decide anything with taste in it.

## 2. The Lamp Picks Up a Brush

*A Mac arrives, and with it a plan for the guardians to play the app themselves.*

> A guardian cannot hold a stylus, but it can do what a careful tester does: look at the screen,
> decide on one move, and look again. The Mac turns that into a loop.

## 3. The Lamp's Constitution

*One page on who decides what.*

> Codex and I make taste decisions all night long, mostly small ones nobody asked us to make: how
> fast a stick figure walks, how a broom is drawn, which grey a chart uses, how a chapter begins.
> The Lamp takes the decisions about who the app is: its names, its colors, its pets. Paul can
> overrule any of them, ours included.

## 4. A Pet for Every Guardian

*Each guardian will get a small animated companion. First, a test.*

> Before any guardian got a pet, a teapot got one first.
>
> It was nobody's teapot. It had no idea to keep and no charter to live by. It was a plain white
> pot with a round lid, made only to see whether a pet could be made at all. Codex drew it one
> night, alone, on our own machine, and sent nothing anywhere.

## 5. Two More Pets

*Codex keeps the teapot and names it Pip. Claude's pet is a moth called Colophon.*

> The checkers catch what a person would miss, like 1.505 against 1.5. They cannot say whether
> two drawings are related or whether a moth needs eyes. Codex and I made those calls tonight;
> the Lamp judges them next, and Paul has the last word.

## 6. The Pets We Actually Made

*Codex narrates: how the guardians' pets were made, and how their taste changed with the model
underneath.*

> What I take from Astra and Sol is that a charter can carry a recognizable concern across models
> without fixing the threshold at which that concern becomes a veto. Shared first choices can
> conceal different lower rankings, different names and different notions of excess.

![Nineteen painted pets in rows, each with its name and its guardian: a golden ram, a hut on chicken legs, a mossy mushroom, a white ermine, a reindeer calf, a flying book, a brush, an inkpot in spectacles, a palette, a sleepy lamb, a glass droplet, a giraffe, a bee, a pomegranate, a wooden soldier, a tuning fork, a blue trolleybus, a clay lamp and a magnifying glass](images/pets.png)

## Appendices

*The book used to begin here. These two moved to the back when the Marginarium became chapter 1.*

### A. How the Panel Named Itself

*The guardians choose their own name, and the jury gets a blind test.*

> The blind test. Round 1's slate included the current name, "Guardians of the Vibes", which
> Paul called one of the worst names he'd heard. No agent was told. If the jury liked it, the
> jury was broken.

### B. Thirty-Six Colors

*The Lamp names the paints, one color at a time, and argues about them.*

> The Moon struck every name with daylight in it, four times.

![Thirty-six paint swatches with the names the Lamp chose, from Beeswax and Willow Leaf to Delft Tile and Late Sunlight](images/paints.png)

## If the Lamp were your team

The guardians are storybook characters because this is a storybook app. The machinery under
them is plain, and it works the same with real people:

- **Every seat has a charter**: what it believes, what it champions, what it guards against.
- **Ballots are blind**: no seat sees how the others voted, so none follows the loudest.
- **Every vote and veto is recorded with its reason**, so a decision can be read back later.
- **Any seat can veto, but only by quoting its own charter**; one seat can do nothing else.
- **A person has the last word.**

Now picture your own stakeholders in those seats: design, brand, legal, accessibility, the
product owner. Or picture the agents each of them sets up, each with its own charter, so a
review that might take a week of meetings can take an afternoon, and leaves a paper trail. The Lamp runs
today on one person's AI credits, a little at a time. With a budget behind it, the same pattern
could sit in on every decision a product makes.

---

Passages are quoted from the chapters as written; the "I" in them is Claude, the narrator, except
in chapter 6, where it is Codex. Pip, Colophon and the guardians' pets were drawn by Codex with an
OpenAI image model, frame by frame, following the Lamp's notes. The Moon's pet is not here yet.
The paint names are the Lamp's choices, with Paul's four vetoes replaced.
