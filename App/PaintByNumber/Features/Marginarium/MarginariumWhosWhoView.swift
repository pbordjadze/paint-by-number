import Foundation
import SwiftUI

/// Who's Who: everyone the chapters mention, with their pets (`MarginariumCast`). The people and
/// the AI helpers come first, then what the Lamp is, then its guardians team by team; a guardian's
/// card opens its brief (`MarginariumGuardianView`). Teams are lazy rows, and cards play small
/// copies of their pets' cells (`MarginariumSpritePlayer(pet:marginWidth:)`), so a screenful of
/// pets never holds their full sheets.
struct MarginariumWhosWhoView: View {
    @ScaledMetric(relativeTo: .body) private var cardMinimum: CGFloat = 150

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 36) {
                    Text(String(localized: "lamp.intro", defaultValue: "Everyone you'll meet in these chapters, and their pets.",
                                comment: "The Marginarium, Who is Who: the line at the top of the page"))
                        .font(.display(.title3, weight: .semibold))
                        .foregroundStyle(.secondary)

                    group(Text("The people")) {
                        ForEach(MarginariumCast.people) { MarginariumPersonCard(person: $0) }
                    }

                    group(Text("The helpers")) {
                        ForEach(MarginariumCast.helpers) { MarginariumPersonCard(person: $0) }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("The Lamp")
                            .font(.display(.title2))
                            .accessibilityAddTraits(.isHeader)
                        Text(String(localized: "lamp.about",
                                    defaultValue: "The Lamp is a panel of imaginary guardians. Each one guards a single idea about how the app should feel, the way a dragon guards one treasure. They look at design choices, write in the margins, and work in teams of friends who care about similar things. They give advice; a person always decides.",
                                    comment: "The Marginarium, Who is Who: what the Lamp is, above its teams of guardians"))
                        Text(String(localized: "lamp.about.tap", defaultValue: "Tap a guardian to read its brief.",
                                    comment: "The Marginarium, Who is Who: the hint above the guardians' cards"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(MarginariumCast.teams) { team in
                        teamView(team)
                            .id("team-" + team.id)
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.paper)
            .navigationTitle("Who's Who")
            .navigationBarTitleDisplayMode(.large)
            .accessibilityIdentifier("marginarium-whos-who")
            #if DEBUG
            .task { await settleDemo(using: proxy) }
            #endif
        }
    }

    private func group<Cards: View>(_ title: Text, @ViewBuilder cards: () -> Cards) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title
                .font(.display(.title2))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cardMinimum), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12, content: cards)
        }
    }

    private func teamView(_ team: MarginariumTeam) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.display(.title3, weight: .semibold))
                Text(team.purpose)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cardMinimum), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(team.members) { guardian in
                    NavigationLink(value: MarginariumCast.destination(of: guardian)) {
                        MarginariumGuardianCard(guardian: guardian)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("marginarium-guardian-\(guardian.id)")
                }
            }
        }
    }

    #if DEBUG
    /// `marginarium-whos-who-teams` shows the later teams; the others are ready as they open.
    private func settleDemo(using proxy: ScrollViewProxy) async {
        guard ShellDemo.current?.marginariumPath.last == MarginariumCast.whosWho else { return }
        if ShellDemo.current == .marginariumWhosWhoTeams, let team = MarginariumCast.teams.dropFirst(4).first {
            do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
            proxy.scrollTo("team-" + team.id, anchor: .top)
        }
        do { try await Task.sleep(for: .milliseconds(800)) } catch { return }
        DemoMode.markReady()
    }
    #endif
}

/// A guardian's card: its pet (or egg), its name and what it guards, one VoiceOver element.
private struct MarginariumGuardianCard: View {
    let guardian: MarginariumGuardian

    var body: some View {
        VStack(spacing: 8) {
            MarginariumGuardianPet(guardian: guardian, width: 72)
                // The card is the link; the pet only keeps it company here.
                .allowsHitTesting(false)
            Text(guardian.name)
                .font(.display(.headline, weight: .semibold))
            Text(MarginariumGuardianView.guardsLine(guardian))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A person (a monogram) or an AI helper (its pet), with their role and one line.
private struct MarginariumPersonCard: View {
    let person: MarginariumPerson

    var body: some View {
        VStack(spacing: 8) {
            if let pet = MarginariumPet.named(person.pet) {
                MarginariumSpritePlayer(pet: pet, marginWidth: 72)
            } else {
                Text(String(person.name.prefix(1)))
                    .font(.display(.title))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Theme.signature, in: Circle())
                    .padding(.vertical, 7)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 2) {
                Text(person.name)
                    .font(.display(.headline, weight: .semibold))
                Text(person.role)
                    .font(.subheadline)
                    .foregroundStyle(.tint)
            }
            Text(person.line)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("marginarium-person-\(person.id)")
    }
}

/// A guardian's pet, small and captionless beside its name, or with its caption as the page's
/// picture; an egg until it hatches.
struct MarginariumGuardianPet: View {
    let guardian: MarginariumGuardian
    /// Nil for the small, captionless kind.
    var caption: String? = nil
    var width: CGFloat = 96

    var body: some View {
        if guardian.hatched, let pet = MarginariumPet.named(guardian.id) {
            if let caption {
                MarginariumSpritePlayer(pet: pet, caption: caption)
            } else {
                MarginariumSpritePlayer(pet: pet, marginWidth: width)
            }
        } else {
            MarginariumEgg(width: width, caption: caption)
        }
    }
}

/// A guardian's brief, its charter in plain words: its pet, who it is named after, its team, what
/// it guards, and what it believes, loves, watches out for, looks up to and is happiest seeing.
struct MarginariumGuardianView: View {
    let guardian: MarginariumGuardian

    static func guardsLine(_ guardian: MarginariumGuardian) -> String {
        String(localized: "lamp.guards", defaultValue: "Guards \(guardian.guards)",
               comment: "The Marginarium, Who is Who: what a guardian guards, under its name; the argument is the treasure, a lowercase phrase such as \"the storybook feel\"")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                MarginariumGuardianPet(guardian: guardian, caption: guardian.petCaption)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text(guardian.name)
                        .font(.display(.largeTitle))
                        .accessibilityAddTraits(.isHeader)
                    if let after = guardian.after {
                        Text(after)
                            .foregroundStyle(.secondary)
                    }
                    Text(Self.guardsLine(guardian))
                        .font(.display(.title3, weight: .regular))
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 18) {
                    if let team = MarginariumCast.team(of: guardian) {
                        row(Text("Team"), team.name, detail: team.purpose)
                        let others = team.members.filter { $0.id != guardian.id }.map(\.name)
                        if !others.isEmpty {
                            row(Text("Teammates"), others.formatted(.list(type: .and)))
                        }
                    }
                    row(Text("Believes"), guardian.believes)
                    row(Text("Loves"), guardian.loves)
                    row(Text("Watches out for"), guardian.watchesFor)
                    row(Text("Looks up to"), guardian.looksUpTo)
                    row(Text("Happiest when"), guardian.happiestWhen)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .navigationTitle(guardian.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("marginarium-guardian-page")
        #if DEBUG
        .onAppear {
            if ShellDemo.current?.marginariumPath.last == MarginariumCast.destination(of: guardian) {
                DemoMode.markReady()
            }
        }
        #endif
    }

    private func row(_ label: Text, _ text: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A pet that hasn't hatched: a cream egg drawn in the pets' brown ink, rocking now and then
/// (still under Reduce Motion). The pets' art keeps its colors in dark mode, so the egg does too.
struct MarginariumEgg: View {
    let width: CGFloat
    /// Nil on a card, where the card names the guardian and the egg is decoration.
    var caption: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let shell = Color(red: 0.965, green: 0.937, blue: 0.875)
    private static let ink = Color(red: 0.42, green: 0.34, blue: 0.27)

    var body: some View {
        VStack(spacing: 6) {
            egg
                // The pets' cells are 96 × 104; the egg stands in one, a little smaller than a pet.
                .frame(width: width * 0.62, height: width * 0.8)
                .frame(width: width, height: width * 104 / 96, alignment: .bottom)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: caption == nil ? nil : CGFloat.infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption ?? ""))
        .accessibilityHidden(caption == nil)
        .accessibilityIdentifier("marginarium-egg")
    }

    @ViewBuilder
    private var egg: some View {
        let drawn = ZStack {
            EggShape().fill(Self.shell)
            EggSpeckles().fill(Self.ink.opacity(0.28))
            EggShape().stroke(Self.ink, style: StrokeStyle(lineWidth: max(1, width / 48), lineJoin: .round))
        }
        if reduceMotion {
            drawn
        } else {
            // A rest, then a rock and a smaller one, as if something inside is stirring.
            drawn.phaseAnimator([0.0, -7, 6, -3, 0]) { content, angle in
                content.rotationEffect(.degrees(angle), anchor: .bottom)
            } animation: { angle in
                angle == 0 ? .easeInOut(duration: 0.3).delay(2.2) : .easeInOut(duration: 0.22)
            }
        }
    }
}

/// An egg, narrower at the top, filling its rectangle.
nonisolated private struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + w * x, y: rect.minY + h * y) }
        var path = Path()
        path.move(to: point(0.5, 0))
        path.addCurve(to: point(1, 0.62), control1: point(0.82, 0), control2: point(1, 0.3))
        path.addCurve(to: point(0.5, 1), control1: point(1, 0.87), control2: point(0.78, 1))
        path.addCurve(to: point(0, 0.62), control1: point(0.22, 1), control2: point(0, 0.87))
        path.addCurve(to: point(0.5, 0), control1: point(0, 0.3), control2: point(0.18, 0))
        path.closeSubpath()
        return path
    }
}

/// A few freckles on the shell, at fixed places so every egg is the same egg.
nonisolated private struct EggSpeckles: Shape {
    private static let spots: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (0.36, 0.30, 0.035), (0.62, 0.40, 0.045), (0.44, 0.55, 0.03), (0.70, 0.66, 0.035),
        (0.30, 0.72, 0.04), (0.55, 0.82, 0.03), (0.52, 0.20, 0.025),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for spot in Self.spots {
            let r = spot.r * rect.width
            path.addEllipse(in: CGRect(x: rect.minX + spot.x * rect.width - r, y: rect.minY + spot.y * rect.height - r * 0.8,
                                       width: 2 * r, height: 1.6 * r))
        }
        return path
    }
}
