import Foundation

/// What a camera, lens, format, light, rig, filter or finish is, and what it does to the picture,
/// in a sentence or two: for the Cinematography tab, so a name on the specification sheet or in a
/// note can be opened and understood. The most specific entry wins ("Alexa 65" before "Alexa").
public enum CraftGlossary {
    /// An explanation of the name, or nil when there's none.
    public static func explain(_ name: String) -> String? {
        let lowered = " " + name.lowercased() + " "
        return entries.first { entry in entry.keys.contains { lowered.contains($0) } }?.text
    }

    /// The glossary's names written in a sentence ("a long take at magic hour"), each with where
    /// it is and what it is: none overlapping, the most specific first. Only names safe to find in
    /// ordinary prose are looked for ("Venice" may be the festival, "practical" an adjective);
    /// gear is found by `TechSpecs` instead.
    public static func terms(in text: String) -> [(range: Range<String.Index>, name: String, explanation: String)] {
        var found: [(range: Range<String.Index>, name: String, explanation: String)] = []
        for entry in entries where entry.inText {
            for key in entry.keys {
                let word = key.trimmingCharacters(in: .whitespaces)
                let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: word) + #"(?![\p{L}\p{N}])"#
                var start = text.startIndex
                while let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: start..<text.endIndex) {
                    if !found.contains(where: { $0.range.overlaps(range) }) {
                        found.append((range, String(text[range]), entry.text))
                    }
                    start = range.upperBound
                }
            }
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    struct Entry {
        let keys: [String]
        let text: String
        /// Looked for in ordinary sentences too (see `terms(in:)`).
        var inText = false
    }

    static let entries: [Entry] = [
        // Labs and post houses (before "Technicolor" the process and "film").
        Entry(keys: ["technicolor lab", "technicolor laboratory", "kodak film lab", "fotokem", "company 3", "efilm", "picture shop", "light iron", "deluxe", "cinelab"], text: "The lab or post house where the film was developed, scanned or colour graded."),
        // Ways of shooting and lighting (before the gear: "dolly zoom" before "dolly" and "zoom").
        Entry(keys: ["dolly zoom", "vertigo effect", "contra-zoom"], text: "The camera moves towards or away from the subject while the lens zooms the other way: the subject stays the same size while the background stretches or squeezes behind it, a feeling of the world lurching.", inText: true),
        Entry(keys: ["crash zoom", "snap zoom"], text: "A very fast zoom in or out, a jolt of attention, often comic or frantic.", inText: true),
        Entry(keys: ["long take", "long takes", "oner", "oners", "single take", "one take", "unbroken shot", "continuous shot", "continuous take"], text: "A shot that runs a long time without a cut. The scene plays out in real time, the actors and the camera choreographed together, and the tension builds because nothing lets you look away.", inText: true),
        Entry(keys: ["tracking shot", "tracking shots", "travelling shot"], text: "The camera moves along with the action, on a dolly, a vehicle, a Steadicam or a crane, carrying the viewer through the space.", inText: true),
        Entry(keys: ["whip pan", "whip pans", "whip-pan"], text: "A pan so fast the image blurs, used to jump between two things or as a hidden cut.", inText: true),
        Entry(keys: ["rack focus", "pull focus", "focus pull", "focus pulls", "pulling focus"], text: "Shifting the focus during a shot from one thing to another, telling the viewer where to look.", inText: true),
        Entry(keys: ["deep focus"], text: "Near and far both sharp in the same shot, so the viewer chooses where to look; famous from Citizen Kane. It needs a small aperture, a wide lens and a lot of light.", inText: true),
        Entry(keys: ["shallow focus", "shallow depth of field", "depth of field"], text: "How much of the picture, from near to far, is sharp. A shallow depth of field isolates a face against a soft blur; a deep one shows the whole world around it.", inText: true),
        Entry(keys: ["dutch angle", "dutch tilt", "canted angle"], text: "The camera tilted so the horizon slants: unease, a world off balance.", inText: true),
        Entry(keys: ["point of view", "point-of-view", "pov shot", "pov"], text: "A shot through a character's eyes: the viewer sees exactly what they see.", inText: true),
        Entry(keys: ["extreme close-up", "close-up", "close-ups", "closeup", "closeups"], text: "A face (or a detail) filling the frame: the most intimate shot, where a small change in the eyes reads as a big event.", inText: true),
        Entry(keys: ["wide shot", "wide shots", "establishing shot", "long shot"], text: "The whole space in view, people small within it: where we are, and how alone or crowded they are.", inText: true),
        Entry(keys: ["overhead shot", "top shot", "bird's-eye", "bird's eye", "god's-eye", "god's eye"], text: "Looking straight down on the scene: detached, map-like, sometimes fateful.", inText: true),
        Entry(keys: ["low angle", "low-angle"], text: "The camera looking up at someone: they loom, powerful or threatening.", inText: true),
        Entry(keys: ["high angle", "high-angle"], text: "The camera looking down on someone: they seem smaller, exposed or vulnerable.", inText: true),
        Entry(keys: ["slow motion", "slow-motion", "overcranked", "overcranking"], text: "Shot at more frames a second than it's played back, so movement stretches out: a moment made to last.", inText: true),
        Entry(keys: ["time-lapse", "timelapse", "undercranked", "undercranking"], text: "Shot at fewer frames a second than it's played back, so time speeds up: clouds race, crowds flicker.", inText: true),
        Entry(keys: ["frame rate", "frames per second", "fps", "high frame rate", "hfr"], text: "How many pictures a second are taken: 24 is cinema's standard and its familiar motion blur; more is smoother and more real, sometimes too real for drama.", inText: true),
        Entry(keys: ["shutter angle"], text: "How long each frame is exposed. A narrow shutter makes movement crisp and staccato (the battle in Saving Private Ryan); a wide one smears it into a dreamy blur.", inText: true),
        Entry(keys: ["t-stop", "f-stop", "aperture", "wide open"], text: "How far the lens is opened: wide open lets in the most light and gives the shallowest focus; stopped down, more is sharp but more light is needed.", inText: true),
        Entry(keys: ["chiaroscuro"], text: "Strong contrast between light and dark, from Renaissance painting: faces carved out of shadow.", inText: true),
        Entry(keys: ["low-key", "low key lighting"], text: "Lighting with deep shadows and little fill: mystery, menace, film noir.", inText: true),
        Entry(keys: ["high-key", "high key lighting"], text: "Bright, even lighting with few shadows: open, light-hearted, the look of comedies and musicals.", inText: true),
        Entry(keys: ["key light"], text: "The main light on a subject, which sets the direction and mood of the lighting.", inText: true),
        Entry(keys: ["fill light"], text: "A softer light that lifts the shadows the key light leaves; less fill, more drama.", inText: true),
        Entry(keys: ["backlight", "backlit", "backlighting", "rim light", "rim lighting", "edge light"], text: "Light from behind the subject, outlining hair and shoulders with a bright edge and separating them from the background.", inText: true),
        Entry(keys: ["soft light", "soft lighting", "diffused light"], text: "Light from a big or diffused source: gentle shadows with soft edges, flattering and natural.", inText: true),
        Entry(keys: ["hard light", "hard lighting"], text: "Light from a small, direct source: crisp, dark shadows and strong texture.", inText: true),
        Entry(keys: ["bounce", "bounced", "bounce light"], text: "Light reflected off a white card, a wall or a ceiling instead of aimed at the subject: softer and more natural.", inText: true),
        Entry(keys: ["silhouette", "silhouettes", "silhouetted"], text: "A figure seen only as a dark shape against a bright background.", inText: true),
        Entry(keys: ["colour temperature", "color temperature", "kelvin"], text: "How warm or cool light is, measured in kelvin: candlelight and tungsten are orange (about 2000–3200 K), daylight bluer (5600 K and up). Mixing them makes colour contrast.", inText: true),
        Entry(keys: ["lens flare", "lens flares", "flares", "flare"], text: "Light shining into the lens and scattering inside it: streaks, rings and a veil of haze. Once a mistake, now often a choice.", inText: true),
        Entry(keys: ["bokeh"], text: "The look of the out-of-focus parts of the picture: round or oval blobs of light, smooth or busy, depending on the lens.", inText: true),
        Entry(keys: ["grain", "film grain"], text: "The texture of film: tiny specks of silver that dance from frame to frame. Faster stocks and pushing make more of it.", inText: true),
        Entry(keys: ["aspect ratio"], text: "The shape of the frame, its width to its height: 1.33:1 nearly square, 1.85:1 standard widescreen, 2.39:1 the wide 'scope' frame.", inText: true),
        Entry(keys: ["negative space"], text: "Empty space in the frame around the subject: isolation, or room for what's coming.", inText: true),
        Entry(keys: ["symmetry", "symmetrical", "centred framing", "centered framing"], text: "The frame balanced around its centre: formal, controlled, often uncanny (Kubrick, Wes Anderson).", inText: true),
        Entry(keys: ["coverage"], text: "The set of shots taken of a scene (wide, mediums, close-ups) so the editor can cut it together; shooting less coverage commits to fewer, longer shots.", inText: true),
        Entry(keys: ["blocking"], text: "Where the actors and the camera move in a scene, worked out together before shooting.", inText: true),
        Entry(keys: ["storyboard", "storyboards", "storyboarded"], text: "The film drawn shot by shot before shooting, like a comic strip.", inText: true),
        Entry(keys: ["colourist", "colorist", "colour grade", "color grade", "colour grading", "color grading", "grade"], text: "The colour grade: the colourist finishes each shot's colour, contrast and brightness, matching shots and giving the film its final look.", inText: true),
        Entry(keys: ["matte painting", "matte paintings"], text: "A painted background (once on glass, now digital) combined with live action to show places that weren't built.", inText: true),
        Entry(keys: ["forced perspective"], text: "Making things look bigger, smaller or farther away by where they're placed from the camera, a trick done in the shot itself.", inText: true),
        Entry(keys: ["in-camera", "in camera"], text: "Done in the shot itself (with mirrors, lenses, light or timing) rather than added later with visual effects.", inText: true),
        Entry(keys: ["split-screen", "split screen"], text: "Two or more images side by side in one frame.", inText: true),
        Entry(keys: ["telephoto", "long lens", "long lenses"], text: "A lens with a narrow view that flattens depth: background and subject pressed together, everything farther away feeling close.", inText: true),

        // Cameras
        Entry(keys: ["alexa 65"], text: "ARRI's large-format digital camera, its sensor about the size of a 65 mm film frame. The big sensor gives a wider view through the same lens and a shallower focus, so images feel immersive, smooth and close to large-format film.", inText: true),
        Entry(keys: ["alexa mini lf"], text: "A compact large-format ARRI Alexa: the big sensor's look in a body small enough for handheld work, gimbals and car rigs."),
        Entry(keys: ["alexa mini"], text: "A small Super 35 ARRI Alexa built for tight spaces, drones, gimbals and handheld work, with the same colour as its bigger siblings."),
        Entry(keys: ["alexa lf"], text: "ARRI's large-format Alexa: a sensor bigger than Super 35 for a wider, shallower, more immersive image."),
        Entry(keys: ["alexa"], text: "ARRI's digital cinema camera, the most used on feature films since the 2010s, known for natural skin tones and highlights that roll off gently, as film does."),
        Entry(keys: ["d-21", "aaton delta", "penelope delta"], text: "A digital cinema camera from the film-camera makers' first digital years, built and handled much like their film cameras."),
        Entry(keys: ["arricam", "arriflex", "moviecam", "panaflex", "millennium xl", "aaton", "mitchell"], text: "A motion-picture film camera: the image is exposed on celluloid and developed in a lab, which brings film's grain, colour and the way it holds highlights."),
        Entry(keys: ["imax"], text: "The largest film format: 65 mm film running sideways through the camera (15 perforations a frame) or certified digital cameras, with a taller frame (1.43:1 or 1.90:1) and great detail for giant screens. The cameras are big and loud, so they're often kept for spectacle.", inText: true),
        Entry(keys: [" red ", "v-raptor", "komodo"], text: "RED's digital cinema cameras, known for high resolution (4K on the RED One, up to 8K today), which leaves room to reframe and to work with visual effects."),
        Entry(keys: ["venice"], text: "Sony's full-frame digital cinema camera. Its second, high sensitivity setting lets it shoot in very low light with little noise, by streetlight or candlelight."),
        Entry(keys: ["phantom"], text: "A high-speed digital camera that records hundreds to thousands of frames a second, for extreme slow motion."),
        Entry(keys: ["iphone"], text: "Shot on a phone: a tiny, light camera that can go anywhere and feels immediate and personal, with a deep focus and a raw digital texture."),
        Entry(keys: ["gopro"], text: "A tiny action camera with a very wide lens, used to put the viewer somewhere a normal camera won't fit."),
        Entry(keys: ["bolex"], text: "A small spring-wound 16 mm film camera, beloved for its handmade, textured look."),

        // Lenses
        Entry(keys: ["65 mm", "70 mm", "ultra panavision", "super panavision", "todd-ao", "system 65"], text: "65 mm film (shown in 70 mm prints): about three and a half times the area of a 35 mm frame, for very fine grain, rich detail and depth."),
        Entry(keys: ["angénieux", "angenieux"], text: "French lenses best known for their zooms (the Optimo range): sharp but warm, with gentle contrast, letting the camera reframe or push in during a shot without changing lenses."),
        Entry(keys: ["cooke"], text: "British lenses with the \"Cooke look\": gentle contrast, warm colour and a flattering, slightly rounded rendering of faces."),
        Entry(keys: ["master prime", "master anamorphic"], text: "Zeiss/ARRI's sharp, high-contrast lenses with almost no distortion or flare: a clean, precise, modern picture."),
        Entry(keys: ["ultra prime"], text: "Zeiss/ARRI's compact, sharp lenses, a long-time workhorse: crisp and neutral."),
        Entry(keys: ["zeiss super speed"], text: "Fast Zeiss lenses from the 1970s–80s: they gather a lot of light and give a softer, lower-contrast, slightly vintage picture."),
        Entry(keys: ["signature prime"], text: "ARRI's large-format lenses, made to soften the digital edge: smooth focus fall-off and gentle, flattering skin."),
        Entry(keys: ["panavision"], text: "Panavision rents its own cameras and lenses and never sells them; its anamorphic lenses (C, E and G Series) and Primos are behind many classic Hollywood looks."),
        Entry(keys: ["k35", "k-35"], text: "Canon's 1970s lenses: low contrast, warm and dreamy, with a soft glow in the highlights."),
        Entry(keys: ["leica", "summilux"], text: "Leica's cinema lenses: fast and very sharp but gentle, with a rich, three-dimensional rendering."),
        Entry(keys: ["hawk"], text: "Vantage's Hawk anamorphic lenses: strong anamorphic character, often in vintage versions with more flare and softness."),
        Entry(keys: ["lomo"], text: "Soviet-era anamorphic lenses, prized for their swirly, imperfect character, flares and soft edges."),
        Entry(keys: ["baltar"], text: "Bausch & Lomb's classic lenses from Hollywood's golden age: soft, low contrast and glowing."),
        Entry(keys: ["petzval"], text: "A 19th-century lens design with a sharp centre and swirling, blurred edges."),
        Entry(keys: ["anamorphic"], text: "Lenses that squeeze a wide picture onto the frame, unsqueezed later for a widescreen image (usually 2.39:1). Their signature: oval out-of-focus lights, horizontal streak flares, a slight bend at the edges and a shallow, painterly focus.", inText: true),
        Entry(keys: ["spherical"], text: "Ordinary (not anamorphic) lenses: round out-of-focus lights, straighter lines and less flare, for a cleaner, more neutral picture."),
        Entry(keys: ["vintage"], text: "Older lenses with lower contrast, more flare and softer edges, used to take the clinical edge off digital cameras."),
        Entry(keys: ["split diopter"], text: "A half-lens over the main lens that keeps two distances in focus at once, a face close by and another far away, with a soft line between.", inText: true),
        Entry(keys: ["zoom"], text: "A lens whose focal length can change during the shot: the frame tightens or widens without the camera moving."),
        Entry(keys: ["wide-angle", "fisheye", "fish-eye"], text: "A lens with a wide view that exaggerates depth: near things loom, far things recede, and faces close to the lens distort."),
        Entry(keys: ["macro"], text: "A lens that focuses very close, for details too small to see in a normal shot."),
        Entry(keys: ["tilt-shift", "swing-and-tilt"], text: "A lens that can be angled to bend the plane of focus, so only a slice of the frame is sharp (a miniature look), or lines straighten.", inText: true),
        Entry(keys: ["probe"], text: "A long, thin lens that can go where a camera can't, low through miniatures or into small spaces."),

        // Film, format and frame
        Entry(keys: ["vistavision"], text: "35 mm film run sideways so each frame is twice as big: finer grain and more detail, a 1950s format revived for large-scale images.", inText: true),
        Entry(keys: ["super 16", "16 mm"], text: "16 mm film: a smaller frame with visible grain and lighter cameras. It feels intimate, raw or of another time."),
        Entry(keys: ["super 8", "8 mm"], text: "The home-movie gauge: heavy grain and soft, flickering images, used for memories and dreams."),
        Entry(keys: ["35 mm", "super 35"], text: "The standard film gauge of cinema: fine grain, rich colour and the way film holds bright highlights."),
        Entry(keys: ["3-perf", "2-perf"], text: "Fewer perforations a frame on 35 mm film: less film used, and a wider frame shape (2-perf is the Techniscope widescreen)."),
        Entry(keys: ["techniscope"], text: "A 2-perf 35 mm widescreen process of the 1960s: wide frames and more visible grain, the look of many Westerns.", inText: true),
        Entry(keys: ["cinemascope"], text: "The original anamorphic widescreen process of the 1950s, which made wide frames a big-screen standard.", inText: true),
        Entry(keys: ["technicolor"], text: "The three-strip colour process of classic Hollywood: saturated, jewel-like colour."),
        Entry(keys: ["open gate"], text: "Recording the camera's whole sensor, not a cropped part: more picture and more room to reframe.", inText: true),
        Entry(keys: ["eterna", "fuji"], text: "Fujifilm's motion-picture film, cooler and more muted than Kodak's, favoured for its subtle greens and soft contrast."),
        Entry(keys: ["vision3", "vision 3", "500t", "250d", "200t", "50d"], text: "Kodak's colour negative film. The number is its speed and the letter its light: T for tungsten (warm indoor light), D for daylight. 500T, the fast tungsten stock, is behind many night scenes."),
        Entry(keys: ["double-x", "tri-x", "black and white", "black-and-white"], text: "Black and white: without colour the picture becomes shape, texture, light and shadow; faces and contrast carry everything."),
        Entry(keys: ["arriraw", "redcode", "prores raw", "x-ocn", "blackmagic raw"], text: "How the camera recorded: raw formats keep everything the sensor saw, leaving the most freedom to shape the picture in the grade."),
        Entry(keys: ["prores"], text: "Apple ProRes: a compressed video recording, with part of the look already baked in; lighter than raw, with less room in the grade."),

        // Aspect ratios
        Entry(keys: ["2.39", "2.40", "2.35", "2.4:1"], text: "Widescreen \"scope\": the widest common frame. Room for landscapes and groups, empty space around a lonely figure, the classic big-screen shape."),
        Entry(keys: ["2.76", "2.55", "2.20", "2.2:1"], text: "An extra-wide frame from the 1950s–60s widescreen era (2.55:1 early CinemaScope, 2.20:1 70 mm prints, 2.76:1 Ultra Panavision 70), for epic scale."),
        Entry(keys: ["2.00", "2:1"], text: "A 2:1 frame (Univisium): between widescreen and scope, made to work in cinemas and on screens at home."),
        Entry(keys: ["1.85"], text: "Standard widescreen: a little taller than scope, natural for interiors, faces and people talking."),
        Entry(keys: ["1.66"], text: "European widescreen, between the old square frame and 1.85: a slightly taller, classic picture."),
        Entry(keys: ["1.43"], text: "IMAX's full frame, the tallest in modern cinema: it fills your vision and stresses height and scale."),
        Entry(keys: ["1.90"], text: "IMAX's digital frame (1.90:1): taller than scope, for scenes that open up on IMAX screens."),
        Entry(keys: ["1.33", "1.37", "academy", "4:3"], text: "The Academy ratio, nearly square, of classic cinema: it boxes people in and feels intimate, old or confined."),

        // Light
        Entry(keys: ["practicals", "practical"], text: "Lights that are part of the scene (lamps, signs, candles, screens) and also light it, so the light feels real and has a source you can see."),
        Entry(keys: ["tungsten"], text: "Warm incandescent light (about 3200 K): next to daylight it reads golden-orange, the colour of home at night."),
        Entry(keys: ["hmi"], text: "Powerful daylight-coloured lamps, often outside windows to imitate the sun or to light large night exteriors."),
        Entry(keys: ["natural light", "available light"], text: "Lit by the sun, the sky and windows with little added: real and alive, but the shoot must follow the weather and the time of day.", inText: true),
        Entry(keys: ["magic hour", "golden hour"], text: "The short time after sunrise or before sunset when light is low, warm and soft, and shadows are long.", inText: true),
        Entry(keys: ["blue hour"], text: "Twilight, when the sun is down but the sky still glows deep blue: a cool, melancholy light that lasts minutes.", inText: true),
        Entry(keys: ["led volume", "stagecraft", "led wall"], text: "Huge LED screens showing the surroundings, so the background is filmed in camera and the actors are lit by its light.", inText: true),
        Entry(keys: ["skypanel", "kino flo", "litemat", "astera", "led "], text: "Soft panel and tube lights (LED, or fluorescent in older Kino Flos); the LED ones can be set to any colour temperature or tint, for gentle, even light and coloured effects."),
        Entry(keys: ["candle"], text: "Lit by candles: very warm, flickering and dim, which needs fast lenses or sensitive cameras."),
        Entry(keys: ["sodium"], text: "Sodium streetlight: a sickly orange-yellow that flattens colours, the look of a city at night."),
        Entry(keys: ["fluorescent"], text: "Fluorescent tubes: a cold, greenish, flat light that feels institutional and uneasy."),
        Entry(keys: ["day for night"], text: "Shooting in daylight and darkening the picture so it reads as night: you can still see the landscape, an old trick.", inText: true),
        Entry(keys: ["negative fill"], text: "Black flags that take light away instead of adding it, deepening shadows for more shape and mood.", inText: true),
        Entry(keys: ["balloon"], text: "Large glowing balloons lifted over a set, for soft, even light over a wide area, often at night."),
        Entry(keys: ["projection"], text: "Images projected behind or onto actors, filmed in camera, so background and light are real on set."),

        // Grip and movement
        Entry(keys: ["steadicam"], text: "A body-worn stabiliser: the camera glides along with walking actors, smooth but still human, ideal for long moving shots.", inText: true),
        Entry(keys: ["handheld", "hand-held"], text: "The camera on the operator's shoulder: small movements make it feel immediate, nervous and present, like being there.", inText: true),
        Entry(keys: ["dolly"], text: "A wheeled platform, often on track, for smooth, deliberate camera moves: in, out or alongside."),
        Entry(keys: ["technocrane"], text: "A telescopic crane arm that can extend and shrink during the shot, flying the camera in ways a normal crane can't.", inText: true),
        Entry(keys: ["crane"], text: "A camera arm that rises, falls and sweeps, for reveals, height and a sense of scale."),
        Entry(keys: ["russian arm", "ultimate arm"], text: "A crane arm mounted on a fast car, for flowing camera moves around moving vehicles."),
        Entry(keys: ["drone"], text: "A flying camera: aerial views and moves impossible from the ground."),
        Entry(keys: ["gimbal", "ronin", "movi"], text: "A motorised stabiliser that keeps the camera level and smooth whether it's carried, run with or mounted."),
        Entry(keys: ["tripod", "locked-off", "locked off"], text: "A fixed camera: a still frame that observes, lets the scene play out and makes any movement inside it stand out."),
        Entry(keys: ["motion control"], text: "A robot arm that repeats the exact same camera move, so several passes can be layered for visual effects.", inText: true),
        Entry(keys: ["snorricam"], text: "A camera rigged to the actor's body facing them: they stay still in the frame while the world moves around them, disorienting.", inText: true),
        Entry(keys: ["easyrig"], text: "A vest with an arm that carries the camera's weight, for long handheld takes."),
        Entry(keys: ["cable cam", "spidercam"], text: "A camera flying on cables over a set or stadium."),

        // Filters
        Entry(keys: ["pro-mist", "promist", "glimmerglass", "black satin", "black magic", "soft fx", "classic soft", "diffusion"], text: "A diffusion filter: highlights bloom, contrast softens and skin smooths, taking the clinical sharpness off a digital image."),
        Entry(keys: ["fog filter"], text: "A filter that adds a misty glow and lifts the blacks, as if the air were thick."),
        Entry(keys: ["nd filter", "neutral density"], text: "A neutral grey filter that cuts light without changing colour, so the lens can stay open for shallow focus even in sunlight."),
        Entry(keys: ["polari"], text: "A polarising filter: it removes reflections and deepens skies."),
        Entry(keys: ["net on the lens", "stocking"], text: "A fine net or stocking over the lens, the old way to soften the picture and give lights a glow."),

        // Lab, grade and finish
        Entry(keys: ["digital intermediate"], text: "The digital grade: the film is scanned and colour, contrast and texture are finalised on a computer before release.", inText: true),
        Entry(keys: ["bleach bypass", "skip bleach", "silver retention"], text: "Skipping the bleach when developing film keeps silver in the image: colours drain, contrast hardens, the picture turns gritty and metallic.", inText: true),
        Entry(keys: ["push process"], text: "Developing film longer than normal to make up for underexposing it (rating it faster): more grain and contrast, a harder, rougher picture.", inText: true),
        Entry(keys: ["cross process"], text: "Developing film in the wrong chemistry: colours shift wildly and contrast jumps.", inText: true),
        Entry(keys: ["show lut", " lut "], text: "A colour recipe (look-up table) designed with the colourist before the shoot, so the intended look is seen on set and carried into the grade."),
        Entry(keys: ["film emulation"], text: "Digital images given the grain, colour and highlight behaviour of a particular film stock.", inText: true),
        Entry(keys: ["film-out", "film out"], text: "A digitally finished film printed back onto celluloid, which gives it film's texture in projection."),

        // The most general last: "Digital intermediate" and "Film emulation" have their own.
        Entry(keys: ["digital"], text: "Shot digitally: on a sensor rather than film. Cleaner, with no grain unless it's added, and seen at once on set."),
        Entry(keys: [" film ", "celluloid", "photochemical"], text: "Shot on film: exposed on celluloid and developed in a lab. Grain, colour and highlights behave in a way digital still imitates."),
    ]
}
