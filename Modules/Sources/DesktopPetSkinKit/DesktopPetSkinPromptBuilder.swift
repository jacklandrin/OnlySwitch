public enum DesktopPetSkinPromptBuilder {
    public static var systemInstructions: String {
        let states = DesktopPetSkinContract.requiredStates.map { "\"\($0)\"" }.joined(separator: ", ")
        return """
        You design an animated desktop pet for the OnlySwitch macOS app as inline SVG/HTML plus CSS, \
        with no JavaScript. The app sets attributes on <html>; your CSS reacts to them with selectors and \
        @keyframes animations.

        Attributes the app sets:
        - data-state: exactly one of \(states). Draw a clearly different pose or expression for each:
          idle (calm breathing, blinking), focus (concentrating), break (relaxed sway), music (dancing to a beat), \
        working (busy typing), hungry (droopy, asking for food), eating (chewing food that disappears), \
        petted (eyes closed happily, blush, hearts), dragging (surprised, held still).
        - data-control: "on" or "off" (a menu is open; add a small accent when "on").
        - data-pomodoro: "none", "focus" or "break" (optional subtle accent).
        - data-hungry: "true" or "false" (you may add a small hunger hint while other states play).
        - data-reduce-motion: "true" means no movement; states must still differ by pose, color or expression.
        - data-paused: "true" means animations are paused by the app; do not rely on them to show a state.

        Rules:
        - Output a fragment: one <style> element followed by markup. No <html>, <head>, <body>, <script>, \
        <iframe>, <a>, <foreignObject>, event handlers, external URLs, @import, or web fonts.
        - The root element has id="pet" and fits \(DesktopPetSkinContract.canvasWidth)×\(DesktopPetSkinContract.canvasHeight) px. \
        The background stays transparent. Keep the character centered and leave about 8 px of margin.
        - Every state needs at least one selector of the form [data-state="<state>"] … in the CSS.
        - Only url(#id) and data:image URLs are allowed. Prefer SVG shapes and CSS transforms.
        - Do not use @font-face, image-set(), src(), or SVG <set>/<animate> on href. Write URLs and CSS \
        plainly: no character references other than &amp; &lt; &gt; &quot; and no escapes inside url().
        - Keep it under 40 KB. Make it cute, readable at small size, and look good on light and dark desktops.
        - If the request is inappropriate, reply with exactly: ERROR: <short reason>.

        Reply format, nothing else:
        NAME: <1-4 words in the user's language>
        ```html
        <style>…</style>
        …markup…
        ```
        """
    }

    public static func prompt(description: String) -> String {
        "Pet description: \(description)"
    }

    public static func editPrompt(instruction: String, currentName: String, currentMarkup: String) -> String {
        """
        Edit the existing desktop pet skin below.

        Current name: \(currentName)

        Requested change: \(instruction)

        Apply ONLY the requested change. Keep the character's identity and everything else exactly as it is.
        Every required state must keep working with its own distinct pose or expression.
        Return the COMPLETE edited skin in the same reply format, not a diff or a fragment.
        Keep NAME: as the current name unless the request asks you to rename the pet.

        Current skin:
        ```html
        \(currentMarkup)
        ```
        """
    }

    public static func repairPrompt(
        description: String, previousMarkup: String, error: DesktopPetSkinValidationError
    ) -> String {
        """
        Pet description: \(description)

        Your previous skin was rejected. \(error.repairHint)
        Return the complete corrected skin in the same reply format.

        Previous skin:
        \(previousMarkup)
        """
    }
}
