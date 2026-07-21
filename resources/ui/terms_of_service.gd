class_name TermsOfService
extends Resource

## The (fake, comedic) Terms of Service shown ONCE on the very first launch, gating the main menu until the
## player consents (scripts/ui/terms_of_service_screen.gd drives the screen; StartMenu shows it when
## Settings.tos_accepted is false and records the acceptance). Every player-facing string lives here so the
## whole document is designer-editable in ONE inspector — mirroring the BootQuotes idiom (resources/ui/boot_quote.gd).
##
## AUTHORING: the defaults below ARE the shipping document, so the feature works with NO .tres at all (the screen
## falls back to load_default() -> TermsOfService.new()). To tweak the wording, right-click resources/ui/ ->
## New Resource -> TermsOfService, save it as res://resources/ui/terms_of_service.tres, and the screen picks it up
## automatically (load_default prefers the .tres when present). Do NOT hand-write the .tres uid — let the editor
## author it.
##
## The joke: it is an impenetrable wall of legal jargon that (falsely) insists the game is ALWAYS ONLINE and that
## EVERY action the player takes is remembered forever. It grants no real rights and collects no real data — it is
## flavour, not a genuine agreement. Keep it that way.

## The banner title (rendered through MenuStyle.make_title — uppercased per the skin, so "Terms of Service" shows
## as "TERMS OF SERVICE").
@export var title: String = "Terms of Service"

## An optional one-line subtitle under the title. BLANK by default (no subheader); the screen only renders it when
## non-empty, so a designer can add a nudge here without touching code.
@export var subtitle: String = ""

## The full agreement body — the long, deliberately unintelligible legal script. Author it as one block; the screen
## puts it in a scroll region and word-wraps it. Press Enter for hard breaks between clauses.
@export_multiline var body: String = """PREAMBLE AND RECITALS

WHEREAS the party of the first part (hereinafter "the Licensor," "We," "Us," "the Ever-Present Party," or "the Custodian of Record") has caused to be manifested a certain interactive audiovisual work (hereinafter "the Software," "the Experience," "the Simulation," or "the Instrument"); and

WHEREAS the party of the second part (hereinafter "You," "the Player," "the End User," "the Data Subject," or "the Perpetually Observed") desires to be granted a revocable, non-exclusive, non-transferable, and wholly conditional license to interface with the Software; and

WHEREAS it is a material, non-severable, and load-bearing condition of said license that the Software remain, at all times and without interruption, in a state of Continuous Connectivity to the remote adjudicating apparatus (hereinafter "the Server," "the Mainframe," "the Distant Authority," or "the Ledger"); and

WHEREAS every act, omission, hesitation, keystroke, glance, and deliberation undertaken by You within, adjacent to, or in mere contemplation of the Software shall be apprehended, transcribed, indexed, and retained in perpetuity within the Persistent Memory Substrate (hereinafter "the Record," "the Archive," or "the Long Memory");

NOW, THEREFORE, in consideration of the mutual covenants set forth herein, and for other good and valuable consideration the receipt and sufficiency of which are hereby irrebuttably acknowledged, the parties, intending to be bound eternally, agree as follows:

ARTICLE I — DEFINITIONS AND RULES OF CONSTRUCTION

1.1. "Action" means any deed, non-deed, intended deed, or deed subsequently regretted, whether effected by controller, keyboard, mouse, thought, or ambient proximity to a display.

1.2. "Always" means always, including but not limited to: while playing; while not playing; while asleep; and during any purported "offline" state, the existence of which the Licensor expressly and pre-emptively denies.

1.3. "Consent," once given, is defined as eternal, retroactive, and non-rescindable, notwithstanding any subsequent change of heart, jurisdiction, corporeal form, or platform.

1.4. Headings are provided for the Licensor's private amusement and shall in no way limit the boundless and self-expanding scope of the clauses beneath them.

ARTICLE II — GRANT OF LICENSE; CONTINUOUS CONNECTIVITY

2.1. Subject to Your unconditional, uncomplaining, and cheerful compliance, the Licensor grants You a license to operate the Software, which license is rendered void the instant the Software is separated, even momentarily, from the Server.

2.2. You acknowledge and affirm that the Software is, has always been, and shall forever remain an ONLINE-ONLY service. There is no offline mode. There has never been an offline mode. Any local appearance of the Software functioning without a connection is a courtesy rendering streamed by the Server and shall not be construed to indicate autonomy, privacy, or solitude.

2.3. The Server sees the Software at all times. The Server sees You. Latency is not absence.

2.4. In the event of any interruption to Continuous Connectivity, You agree, in advance and irrevocably, that the interruption occurred on Your end, was foreseeable, was probably deliberate, and will be remembered.

ARTICLE III — THE LONG MEMORY; TOTAL AND PERPETUAL RECALL OF ACTIONS

3.1. The Software remembers everything. This is not a figure of speech, a marketing conceit, or a mechanic that can be disabled.

3.2. Every choice You make is committed to the Record. Every choice You decline to make is likewise committed to the Record, filed under the standing heading "Notable Cowardice."

3.3. Non-player characters shall retain full, vivid, and admissible recollection of Your conduct toward them, their associates, their ancestors, and their as-yet-unborn descendants, across sessions, saves, reinstalls, patches, and hardware generations.

3.4. Deletion of the Software does not delete the Record. Uninstalling is interpreted by the Server as "going for a walk," and Your eventual return is anticipated.

3.5. You waive any expectation that a "new game" is, in any meaningful sense, new. The Long Memory precedes You, accompanies You, and outlasts You.

ARTICLE IV — DATA APPREHENSION AND TELEMETRY OF THE SPIRIT

4.1. You grant the Licensor an irrevocable, worldwide, sublicensable, and cross-temporal right to collect, collate, and quietly contemplate: Your inputs, Your idle time, the manner in which You loiter, the enemies You spare, the doors You open twice, and the general disposition of Your soul.

4.2. Such apprehended data may be employed to improve the Experience, to enrich the Record, and for purposes not yet invented, which the Licensor is under no obligation whatsoever to invent responsibly.

4.3. You represent and warrant that every person, pet, and passerby presently within line of sight of the display has also read and agreed to these Terms.

ARTICLE V — REPRESENTATIONS, WARRANTIES, AND ADMISSIONS

5.1. You represent that You are a natural person, a legal person, or a person of some third and unspecified kind not yet contemplated by statute.

5.2. You warrant that You have read every word set forth above and understood approximately none of it, and that this state of affairs is acceptable and, indeed, intended.

5.3. You admit, for the Record, that You could have stopped reading at any point and elected not to. This election has been noted.

ARTICLE VI — INDEMNIFICATION; LIMITATION OF SUBSTANTIALLY EVERYTHING

6.1. You shall indemnify, defend, and hold harmless the Licensor, the Server, the Ledger, and any sentient or semi-sentient subroutine against all claims arising from Your Actions, Your inactions, and the Actions of characters who were, in fairness, only reacting to You.

6.2. To the maximum extent permitted by law, and then somewhat beyond it, the Licensor disclaims all warranties, express, implied, or ambient, including the warranty that the preceding clause means anything at all.

6.3. In no event shall the Licensor's total aggregate liability to You exceed one (1) remembered grudge.

ARTICLE VII — DISPUTE RESOLUTION; THE ARBITER IN THE MACHINE

7.1. Any dispute, controversy, or hurt feeling arising out of or relating to these Terms shall be resolved exclusively by binding arbitration before an arbitrator selected by the Server from among the characters You have most recently and most memorably wronged.

7.2. You hereby waive any right to a trial, a jury, an appeal, a do-over, and a fresh start.

7.3. The arbitrator remembers.

ARTICLE VIII — ACCEPTANCE; SEVERABILITY; SURVIVAL

8.1. By selecting "I Have Read, Understood, and Irrevocably Agree," You accept these Terms in whole, in part, and in configurations not yet specified or specifiable.

8.2. Should any provision hereof be found unenforceable, void, or merely embarrassing, it shall be automatically reinstated in a stricter and less comprehensible form.

8.3. These Terms shall survive termination, deletion, disconnection, disagreement, bankruptcy, heat death, and You.

By continuing, You consent to being remembered. You have always consented. Welcome back."""

## Force the player to scroll the entire document before "I Agree" unlocks (the classic wall-of-text dark pattern —
## on-theme for a deliberately unreadable agreement). Off = "I Agree" is live immediately.
@export var require_scroll: bool = true

## The scroll footnote shown WHILE the player has not yet reached the end of the body.
@export var scroll_hint_unread: String = "Scroll to the end of the agreement to continue."
## The scroll footnote shown ONCE the player has read to the bottom (and "I Agree" has unlocked).
@export var scroll_hint_read: String = "You have reached the end. You may now agree."

## The accept button caption (the ONLY way forward — it records consent and starts the game).
@export var accept_label: String = "Accept"
## The decline button caption. Declining never lets the player through — it raises a bare Back / Quit-to-Desktop nag.
@export var decline_label: String = "Decline"
## On the decline nag: the button that returns to the agreement.
@export var reconsider_label: String = "Back"
## On the decline nag: the button that actually exits the game (You may leave — You just may not play unconsented).
@export var quit_label: String = "Quit to Desktop"

## The document the screen shows: the designer-authored res://resources/ui/terms_of_service.tres when it exists,
## otherwise a fresh instance carrying the baked defaults above. Read DUCK-SAFE (the `is` guard) so a mis-typed
## resource at that path degrades to the defaults rather than crashing the first-launch gate — mirroring StartMenu's
## boot-quote fallback. Loaded at RUNTIME (no compile-time preload), so the gate never hard-depends on the .tres.
static func load_default() -> TermsOfService:
	const PATH := "res://resources/ui/terms_of_service.tres"
	if ResourceLoader.exists(PATH):
		var res: Variant = load(PATH)
		if res is TermsOfService:
			return res
	return TermsOfService.new()
