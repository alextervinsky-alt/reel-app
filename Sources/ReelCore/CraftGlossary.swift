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

    struct Entry {
        let keys: [String]
        let text: String
    }

    static let entries: [Entry] = [
        // Cameras
        Entry(keys: ["alexa 65"], text: "ARRI's large-format digital camera, its sensor about the size of a 65 mm film frame. The big sensor gives a wider view through the same lens and a shallower focus, so images feel immersive, smooth and close to large-format film."),
        Entry(keys: ["alexa mini lf"], text: "A compact large-format ARRI Alexa: the big sensor's look in a body small enough for handheld work, gimbals and car rigs."),
        Entry(keys: ["alexa mini"], text: "A small Super 35 ARRI Alexa built for tight spaces, drones, gimbals and handheld work, with the same colour as its bigger siblings."),
        Entry(keys: ["alexa lf"], text: "ARRI's large-format Alexa: a sensor bigger than Super 35 for a wider, shallower, more immersive image."),
        Entry(keys: ["alexa"], text: "ARRI's digital cinema camera, the most used on feature films since the 2010s, known for natural skin tones and highlights that roll off gently, as film does."),
        Entry(keys: ["arricam", "arriflex", "moviecam", "panaflex", "millennium xl", "aaton", "mitchell"], text: "A motion-picture film camera: the image is exposed on celluloid and developed in a lab, which brings film's grain, colour and the way it holds highlights."),
        Entry(keys: ["imax"], text: "The largest film format: 65 mm film running sideways through the camera (15 perforations a frame) or certified digital cameras, with a taller frame (1.43:1 or 1.90:1) and great detail for giant screens. The cameras are big and loud, so they're often kept for spectacle."),
        Entry(keys: [" red ", "v-raptor", "komodo"], text: "RED's digital cinema cameras, known for very high resolution (6K–8K), which leaves room to reframe and to work with visual effects."),
        Entry(keys: ["venice"], text: "Sony's full-frame digital cinema camera. Its second, high sensitivity setting lets it shoot in very low light with little noise, by streetlight or candlelight."),
        Entry(keys: ["phantom"], text: "A high-speed digital camera that records hundreds to thousands of frames a second, for extreme slow motion."),
        Entry(keys: ["iphone"], text: "Shot on a phone: a tiny, light camera that can go anywhere and feels immediate and personal, with a deep focus and a raw digital texture."),
        Entry(keys: ["gopro"], text: "A tiny action camera with a very wide lens, used to put the viewer somewhere a normal camera won't fit."),
        Entry(keys: ["bolex"], text: "A small spring-wound 16 mm film camera, beloved for its handmade, textured look."),

        // Lenses
        Entry(keys: ["anamorphic"], text: "Lenses that squeeze a wide picture onto the frame, unsqueezed later for a 2.39:1 widescreen image. Their signature: oval out-of-focus lights, horizontal streak flares, a slight bend at the edges and a shallow, painterly focus."),
        Entry(keys: ["spherical"], text: "Ordinary (not anamorphic) lenses: round out-of-focus lights, straighter lines and less flare, for a cleaner, more neutral picture."),
        Entry(keys: ["angénieux", "angenieux"], text: "French lenses best known for their zooms (the Optimo range): gentle, warm and slightly soft, letting the camera reframe or push in during a shot without changing lenses."),
        Entry(keys: ["cooke"], text: "British lenses with the \"Cooke look\": gentle contrast, warm colour and a flattering, slightly rounded rendering of faces."),
        Entry(keys: ["master prime", "master anamorphic"], text: "Zeiss/ARRI's sharp, high-contrast lenses with almost no distortion or flare: a clean, precise, modern picture."),
        Entry(keys: ["ultra prime"], text: "Zeiss/ARRI's compact, sharp lenses, a long-time workhorse: crisp and neutral."),
        Entry(keys: ["super speed"], text: "Fast Zeiss lenses from the 1970s–80s: they gather a lot of light and give a softer, lower-contrast, slightly vintage picture."),
        Entry(keys: ["signature prime"], text: "ARRI's large-format lenses, made to soften the digital edge: smooth focus fall-off and gentle, flattering skin."),
        Entry(keys: ["panavision"], text: "Panavision rents its own cameras and lenses and never sells them; its anamorphic lenses (C, E and G Series) and Primos are behind many classic Hollywood looks."),
        Entry(keys: ["k35", "k-35"], text: "Canon's 1970s lenses: low contrast, warm and dreamy, with a soft glow in the highlights."),
        Entry(keys: ["leica", "summilux"], text: "Leica's cinema lenses: fast and very sharp but gentle, with a rich, three-dimensional rendering."),
        Entry(keys: ["hawk"], text: "Vantage's Hawk anamorphic lenses: strong anamorphic character, often in vintage versions with more flare and softness."),
        Entry(keys: ["lomo"], text: "Soviet-era anamorphic lenses, prized for their swirly, imperfect character, flares and soft edges."),
        Entry(keys: ["baltar"], text: "Bausch & Lomb's classic lenses from Hollywood's golden age: soft, low contrast and glowing."),
        Entry(keys: ["petzval"], text: "A 19th-century lens design with a sharp centre and swirling, blurred edges."),
        Entry(keys: ["vintage"], text: "Older lenses with lower contrast, more flare and softer edges, used to take the clinical edge off digital cameras."),
        Entry(keys: ["split diopter"], text: "A half-lens over the main lens that keeps two distances in focus at once, a face close by and another far away, with a soft line between."),
        Entry(keys: ["zoom"], text: "A lens whose focal length can change during the shot: the frame tightens or widens without the camera moving."),
        Entry(keys: ["wide-angle", "fisheye", "fish-eye"], text: "A lens with a wide view that exaggerates depth: near things loom, far things recede, and faces close to the lens distort."),
        Entry(keys: ["macro"], text: "A lens that focuses very close, for details too small to see in a normal shot."),
        Entry(keys: ["tilt-shift", "swing-and-tilt"], text: "A lens that can be angled to bend the plane of focus, so only a slice of the frame is sharp (a miniature look), or lines straighten."),
        Entry(keys: ["probe"], text: "A long, thin lens that can go where a camera can't, low through miniatures or into small spaces."),

        // Film, format and frame
        Entry(keys: ["65 mm", "70 mm", "ultra panavision", "todd-ao", "system 65"], text: "65 mm film (shown in 70 mm prints): about three and a half times the area of a 35 mm frame, for very fine grain, rich detail and depth."),
        Entry(keys: ["vistavision"], text: "35 mm film run sideways so each frame is twice as big: finer grain and more detail, a 1950s format revived for large-scale images."),
        Entry(keys: ["super 16", "16 mm"], text: "16 mm film: a smaller frame with visible grain and lighter cameras. It feels intimate, raw or of another time."),
        Entry(keys: ["super 8", "8 mm"], text: "The home-movie gauge: heavy grain and soft, flickering images, used for memories and dreams."),
        Entry(keys: ["35 mm", "super 35"], text: "The standard film gauge of cinema: fine grain, rich colour and the way film holds bright highlights."),
        Entry(keys: ["3-perf", "2-perf"], text: "Fewer perforations a frame on 35 mm film: less film used, and a wider frame shape (2-perf is the Techniscope widescreen)."),
        Entry(keys: ["techniscope"], text: "A 2-perf 35 mm widescreen process of the 1960s: wide frames and more visible grain, the look of many Westerns."),
        Entry(keys: ["cinemascope"], text: "The original anamorphic widescreen process of the 1950s, which made wide frames a big-screen standard."),
        Entry(keys: ["technicolor"], text: "The three-strip colour process of classic Hollywood: saturated, jewel-like colour."),
        Entry(keys: ["open gate"], text: "Recording the camera's whole sensor, not a cropped part: more picture and more room to reframe."),
        Entry(keys: ["vision3", "vision 3", "500t", "250d", "200t", "50d"], text: "Kodak's colour negative film. The number is its speed and the letter its light: T for tungsten (warm indoor light), D for daylight. 500T, the fast tungsten stock, is behind many night scenes."),
        Entry(keys: ["double-x", "tri-x", "black and white", "black-and-white"], text: "Black and white: without colour the picture becomes shape, texture, light and shadow; faces and contrast carry everything."),
        Entry(keys: ["eterna", "fuji"], text: "Fujifilm's motion-picture film, cooler and more muted than Kodak's, favoured for its subtle greens and soft contrast."),
        Entry(keys: ["arriraw", "redcode", "prores", "x-ocn", "blackmagic raw"], text: "How the camera recorded: raw formats keep everything the sensor saw, leaving the most freedom to shape the picture in the grade."),

        // Aspect ratios
        Entry(keys: ["2.39", "2.40", "2.35", "2.4:1"], text: "Widescreen \"scope\": the widest common frame. Room for landscapes and groups, empty space around a lonely figure, the classic big-screen shape."),
        Entry(keys: ["2.76", "2.55", "2.20", "2.2:1"], text: "An extra-wide frame from the 70 mm era, for epic scale."),
        Entry(keys: ["2.00", "2:1"], text: "A 2:1 frame (Univisium): between widescreen and scope, made to work in cinemas and on screens at home."),
        Entry(keys: ["1.85"], text: "Standard widescreen: a little taller than scope, natural for interiors, faces and people talking."),
        Entry(keys: ["1.66"], text: "European widescreen, between the old square frame and 1.85: a slightly taller, classic picture."),
        Entry(keys: ["1.43"], text: "IMAX's full frame, almost square and very tall: it fills your vision and stresses height and scale."),
        Entry(keys: ["1.90"], text: "IMAX's digital frame: taller than ordinary widescreen, for scenes that open up on IMAX screens."),
        Entry(keys: ["1.33", "1.37", "academy", "4:3"], text: "The Academy ratio, nearly square, of classic cinema: it boxes people in and feels intimate, old or confined."),

        // Light
        Entry(keys: ["practicals", "practical"], text: "Lights that are part of the scene (lamps, signs, candles, screens) and also light it, so the light feels real and has a source you can see."),
        Entry(keys: ["tungsten"], text: "Warm incandescent light (about 3200 K): next to daylight it reads golden-orange, the colour of home at night."),
        Entry(keys: ["hmi"], text: "Powerful daylight-coloured lamps, often outside windows to imitate the sun or to light large night exteriors."),
        Entry(keys: ["natural light", "available light"], text: "Lit by the sun, the sky and windows with little added: real and alive, but the shoot must follow the weather and the time of day."),
        Entry(keys: ["magic hour", "golden hour"], text: "The short time after sunrise or before sunset when light is low, warm and soft, and shadows are long."),
        Entry(keys: ["blue hour"], text: "Twilight, when the sun is down but the sky still glows deep blue: a cool, melancholy light that lasts minutes."),
        Entry(keys: ["led volume", "stagecraft", "led wall"], text: "Huge LED screens showing the surroundings, so the background is filmed in camera and the actors are lit by its light."),
        Entry(keys: ["skypanel", "kino flo", "litemat", "astera", "led "], text: "Soft LED or fluorescent lights whose colour can be set precisely, for gentle, even light and coloured effects."),
        Entry(keys: ["candle"], text: "Lit by candles: very warm, flickering and dim, which needs fast lenses or sensitive cameras."),
        Entry(keys: ["sodium"], text: "Sodium streetlight: a sickly orange-yellow that flattens colours, the look of a city at night."),
        Entry(keys: ["fluorescent"], text: "Fluorescent tubes: a cold, greenish, flat light that feels institutional and uneasy."),
        Entry(keys: ["day for night"], text: "Shooting in daylight and darkening the picture so it reads as night: you can still see the landscape, an old trick."),
        Entry(keys: ["negative fill"], text: "Black flags that take light away instead of adding it, deepening shadows for more shape and mood."),
        Entry(keys: ["balloon"], text: "Large glowing balloons lifted over a set, for soft, even light over a wide area, often at night."),
        Entry(keys: ["projection"], text: "Images projected behind or onto actors, filmed in camera, so background and light are real on set."),

        // Grip and movement
        Entry(keys: ["steadicam"], text: "A body-worn stabiliser: the camera glides along with walking actors, smooth but still human, ideal for long moving shots."),
        Entry(keys: ["handheld", "hand-held"], text: "The camera on the operator's shoulder: small movements make it feel immediate, nervous and present, like being there."),
        Entry(keys: ["dolly"], text: "A wheeled platform, often on track, for smooth, deliberate camera moves: in, out or alongside."),
        Entry(keys: ["technocrane"], text: "A telescopic crane arm that can extend and shrink during the shot, flying the camera in ways a normal crane can't."),
        Entry(keys: ["crane"], text: "A camera arm that rises, falls and sweeps, for reveals, height and a sense of scale."),
        Entry(keys: ["russian arm", "ultimate arm"], text: "A crane arm mounted on a fast car, for flowing camera moves around moving vehicles."),
        Entry(keys: ["drone"], text: "A flying camera: aerial views and moves impossible from the ground."),
        Entry(keys: ["gimbal", "ronin", "movi"], text: "A motorised stabiliser that keeps the camera level and smooth whether it's carried, run with or mounted."),
        Entry(keys: ["tripod", "locked-off", "locked off"], text: "A fixed camera: a still frame that observes, lets the scene play out and makes any movement inside it stand out."),
        Entry(keys: ["motion control"], text: "A robot arm that repeats the exact same camera move, so several passes can be layered for visual effects."),
        Entry(keys: ["snorricam"], text: "A camera rigged to the actor's body facing them: they stay still in the frame while the world moves around them, disorienting."),
        Entry(keys: ["easyrig"], text: "A vest with an arm that carries the camera's weight, for long handheld takes."),
        Entry(keys: ["cable cam", "spidercam"], text: "A camera flying on cables over a set or stadium."),

        // Filters
        Entry(keys: ["pro-mist", "promist", "glimmerglass", "black satin", "black magic", "soft fx", "classic soft", "diffusion"], text: "A diffusion filter: highlights bloom, contrast softens and skin smooths, taking the clinical sharpness off a digital image."),
        Entry(keys: ["fog filter"], text: "A filter that adds a misty glow and lifts the blacks, as if the air were thick."),
        Entry(keys: ["nd filter", "neutral density"], text: "A neutral grey filter that cuts light without changing colour, so the lens can stay open for shallow focus even in sunlight."),
        Entry(keys: ["polari"], text: "A polarising filter: it removes reflections and deepens skies."),
        Entry(keys: ["net on the lens", "stocking"], text: "A fine net or stocking over the lens, the old way to soften the picture and give lights a glow."),

        // Lab, grade and finish
        Entry(keys: ["digital intermediate"], text: "The digital grade: the film is scanned and colour, contrast and texture are finalised on a computer before release."),
        Entry(keys: ["bleach bypass", "skip bleach", "silver retention"], text: "Skipping the bleach when developing film keeps silver in the image: colours drain, contrast hardens, the picture turns gritty and metallic."),
        Entry(keys: ["push process"], text: "Developing film longer than normal to make it more sensitive: more grain and contrast, a harder, rougher picture."),
        Entry(keys: ["cross process"], text: "Developing film in the wrong chemistry: colours shift wildly and contrast jumps."),
        Entry(keys: ["show lut", " lut "], text: "A colour recipe (look-up table) designed with the colourist before the shoot, so the intended look is seen on set and carried into the grade."),
        Entry(keys: ["film emulation"], text: "Digital images given the grain, colour and highlight behaviour of a particular film stock."),
        Entry(keys: ["film-out", "film out"], text: "A digitally finished film printed back onto celluloid, which gives it film's texture in projection."),
        Entry(keys: ["fotokem", "company 3", "efilm", "picture shop", "light iron", "deluxe", "cinelab"], text: "The lab or post house where the film was developed, scanned or colour graded."),

        // The most general last: "Digital intermediate" and "Film emulation" have their own.
        Entry(keys: ["digital"], text: "Shot digitally: on a sensor rather than film. Cleaner, with no grain unless it's added, and seen at once on set."),
        Entry(keys: [" film ", "celluloid", "photochemical"], text: "Shot on film: exposed on celluloid and developed in a lab. Grain, colour and highlights behave in a way digital still imitates."),
    ]
}
