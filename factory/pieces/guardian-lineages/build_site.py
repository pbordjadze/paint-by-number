"""Builds the whole contact sheet: the latest batch above the pilot (version 3), older versions below.

usage: python3 build_site.py <site dir>   (on lenovo-homelab: ~/pets-drafts/site/lineages)
"""
import json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ORDER = ['pirosmani', 'emily-dickinson', 'balanchine', 'sen-no-rikyu', 'keynes',
         'bulat-okudzhava', 'glassblower', 'snow-queen', 'nutcracker', 'baba-yaga']


def main(site):
    batch = json.load(open(os.path.join(HERE, 'lineages-batch2.json'), encoding='utf-8'))
    pilot = json.load(open(os.path.join(HERE, 'lineages-v3.json'), encoding='utf-8'))
    rows = sorted(batch['guardians'], key=lambda g: ORDER.index(g['id']))
    rows[0]['section'] = 'Ten more, October 23'
    pilot['guardians'][0]['section'] = 'The pilot'
    page = {'pick_prefix': 'lineage-v3-', 'guardians': rows + pilot['guardians'], 'lede': (
        "<p>Paul, Oct 23: the same shift for every guardian, three jumps back along a line of influence. "
        "The lens, codified in <code>RULE.md</code>: <i>carry the guardian's idea back, not its picture.</i> At each step, how would that tradition, with its own tools and knowledge, make this guardian's subject? "
        "Each guardian has a card (an essence that stays, at most a rhyme or two, and what gets left behind), and for the jumps Codex saw no image, only the card. "
        "Plate 0 is today's guardian re-made, its approved drawing beside it. Every jump is sourced under its row; <i>spiritual</i> means no documented tie was found.</p>"
        "<p>Every row ends with a <b>wildcard</b>, one plate made by breaking the rule on purpose. The pilot's four all broke it the same way (the real thing, today); "
        "you kept them. The new ten were each given a different suggested break (sideways, forward, a scene, an absence, a hybrid, what it inspired, scale, a new subject, the inside, a copy) "
        "and told not to repeat that one. Mock-ups only: nothing goes into the app. Labels are typeset, not drawn by the model.</p>"
        "<p>Earlier versions of the pilot: <a href=\"v2/\" style=\"color:#e7c98f\">version 2</a> (only the shape kept), "
        "<a href=\"v1/\" style=\"color:#e7c98f\">version 1</a> (the objects kept).</p>")}
    with tempfile.TemporaryDirectory() as tmp:
        plates = os.path.join(tmp, 'plates'); os.makedirs(plates)
        for d in ('plates-v3', 'plates-batch2'):
            for f in os.listdir(os.path.join(HERE, d)):
                shutil.copy(os.path.join(HERE, d, f), plates)
        json.dump(page, open(os.path.join(tmp, 'page.json'), 'w'), ensure_ascii=False)
        new = site.rstrip('/') + '.new'
        shutil.rmtree(new, ignore_errors=True)
        build = os.path.join(HERE, 'build_page.py')
        subprocess.run(['python3', build, os.path.join(tmp, 'page.json'), plates, new], check=True)
        subprocess.run(['python3', build, os.path.join(HERE, 'lineages-v2.json'), os.path.join(HERE, 'plates-v2'), os.path.join(new, 'v2')], check=True)
        subprocess.run(['python3', build, os.path.join(HERE, 'lineages.json'), os.path.join(HERE, 'plates'), os.path.join(new, 'v1')], check=True)
        v2 = os.path.join(new, 'v2', 'index.html')
        open(v2, 'w').write(open(v2).read().replace('<a href="v1/"', '<a href="../v1/"'))
        shutil.rmtree(site, ignore_errors=True)
        os.rename(new, site)
        subprocess.run(['chmod', '-R', 'a+rX', site], check=True)


if __name__ == '__main__':
    main(sys.argv[1])
