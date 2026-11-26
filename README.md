# Reel

A personal Mac app that scans film drives, recognises each film from its file name, and shows the films as a library that helps decide what to watch. Bonus material in a film's folder (interviews, trailers, an `Extras` folder, subtitles, notes) stays with its film instead of showing up as a film of its own. Reel never changes, moves or writes film files and never writes to a film drive: a scan only reads folder listings (names, sizes, dates), and a file is opened only when you press Play or open an extra.

Apple Silicon, macOS 15 or later.

## What's new in 1.11.4

- **A film page in three tabs:** Overview now has what people say (the verdict, the scores, the critics' consensus, what people like and don't) under the story, and Behind the Film no longer opens on frames from the film.
- **Rotten Tomatoes for every film,** not just yours: previews in Explore, For You, New Releases and the Wishlist, and the critics' scores behind Most Acclaimed, take the Tomatometer from Wikidata when OMDb has none (one query for many films, each film asked once a session).

## What's new in 1.11.3

- **Smoother scrolling.** While a page scrolls, macOS asks the window what's under the pointer on every frame; on Alex's Mac answering took half of Reel's main-thread work, as every poster's click, hover and text areas were checked. Posters and cards now answer only while they're under the pointer (the grid and each page know which one is), and a poster clicked before one is lifted opens all the same. On CI's Mac one such check over All Films went from 768 to 259 µs (a window of plain tiles takes 106).

## What's new in 1.11.2

- **The sidebar as in 1.10.10, with New Releases.** Recommended, For You and Wishlist are their own rows again, and Explore's shelves are separate rows again (1.11's merge is undone). **New Releases** is a new tab: In Cinemas Now, Coming Soon, **New at Home** (recently in cinemas, now out to stream, rent or buy online) and **New on Blu-ray** (out on disc in the last three months).
- **Lists in chapters.** Under the search: Your Lists (Start Here, Your Progress, Complete the Set), The Canon, Festivals & Awards, and Rankings. Every list is kept.
- **Rotten Tomatoes is back.** OMDb no longer sends it, and the refresh of 24 Nov wrote "none" over the stored scores. A refresh now never removes a score it doesn't send, and the Tomatometer comes from Wikidata (its latest dated score) when OMDb has none.
- **Frames from the Film:** the same stills in another order no longer clear the check.
- **Settings › Scrolling** counts each page on its own, with the share of frames missed.
- (1.11.1) Posters read ahead as Reel opens are drawn at once (1.11.0 left the first rows of All Films blank).

## What's new in 1.11

1.11 keeps the features that work well, makes them better, and makes Reel smoother.

- **Your data is safer.** Your Notes now keeps every copy's match (so a rebuilt library never matches a known file again, and your own fixes still win) and the frames you said aren't from the film. Frame removals made before 1.11 are carried over at first launch by running the same on-device check again. A film where that can't be done is skipped, and the count goes to `Migration log.txt` in the Reel folder (counts only). A Your Notes written by a newer Reel opens read-only, and a damaged one shows its newest readable Safety Copy with Restore. Settings.json gets daily Safety Copies too.
- **A smaller, faster library file.** `Library.json` moves to format 7: each film's info is kept once, not once per copy, so a library with Backup copies is about 40% of the size. On CI, 300 films open in under 0.1 s. It is saved every 30 seconds while film info is being looked up, and once at the end.
- **Smoother.** One pointer tracker per grid instead of one per poster, posters drawn with their frame once, file names read once, and film pages that redraw only for their own film. Settings › Diagnostics › Scrolling counts the frames shown and missed on each page at the screen's own rate.
- **Lists.** New: the Sight and Sound directors' poll (2022), AFI's 100 Years…100 Movies (2007), the Oscar for Best Documentary, Venice's Grand Jury Prize, the Berlinale's Silver Bear Grand Jury Prize, the European Film Award for Best Cinematographer, and the Most Acclaimed of each decade. The Lists page is grouped into The Canon, Festivals, Awards, Cinematography and Rankings, and its search finds Reel's own lists. Winners & Nominees sits under each award list's title, and a nomination now adds a third of its list's weight to a film that's on another list.
- **Reviews** are read with new rules. A like or dislike needs words that judge one part of the film, with nothing said the other way. Questions, other films, wishes and plot summaries are left out, and quotes are whole sentences that never run into the next paragraph. On 30 well-known films that weren't used to set the rules, 83% of likes and 77% of dislikes were right (1.10: about 75%), short of the 95% aimed for. Each film's reviews are read again once.
- **Removed:** the Cinematography tab and the Shot on filter. Their facts were right about 94% of the time but found for only a third of films. Frames from the Film moved to Behind the Film, shown when at least four real frames are found. The Shot on and facts you marked Not Right stay in Your Notes as they are. The old readings folder can be moved to the Trash from Settings.
- **Smaller fixes.** Moods: a true story alone no longer makes a film Inspiring, keywords match whole words, and every film with genres has a mood. Did You Know shows up to five whole sentences. The ratings line shows TMDB only when IMDb, Rotten Tomatoes and Metacritic are all missing. Year in Film's panels fill their rows. Poster size and posters or list are remembered between launches.

**Older Reels.** Reel 1.10.10 and older won't write over a 1.11 library. If an older Reel saves Your Notes, it drops the remembered matches and frame removals: the matches come back at the next 1.11 launch, and frame removals can be restored from a Safety Copy.

## The library

All Films opens in a random order, different each time you come back to it, or sorted by title, year, rating, date added or running time. Search sits beside the title (⌘F). It forgives a slip in a title or a name and understands stand-ins ("cartoon" finds animation, "docs" documentaries). Filters: mood, length and language. Posters or a list, at the size you choose.

Under the pointer, a poster shows its ratings (IMDb, Rotten Tomatoes, Metacritic), when it would end, and its subtitles. Space opens a quick preview, and the moon adds it to Tonight. **New Arrivals** shows films found in the last 14 days. **Unwatched** has **Seen It?**, one poster at a time. A drive marked as the Backup is compared with the main drive, and **Not on Backup** lists what's missing or only half copied.

A scan removes films only when it read the whole drive. When a folder can't be read, nothing is removed. A scan that would remove many films asks first.

## Tonight

Your shortlist for the evening, compared side by side: year and genres, director and leads, ratings, verdict, premise, end time, moods, subtitles and quality, and the lists each is on. **Decide for Us** picks one, and the shortlist clears itself at 6 in the morning. "Not tonight" keeps a film out for two weeks.

## A film's page

- **Overview:** At a Glance (director, writers, camera, music, editor, design, aspect ratio, language, the file, subtitles, where your copies are, your status), Pair It With (a double feature from your library, with why), From the Same People, and More Like This.
- **Reviews:** what people like and don't like, from TMDB's user reviews and the critics Wikipedia quotes, with the critics' consensus and awards.
- **Behind the Film:** Frames from the Film, then Did You Know (up to five facts), then the film's Wikipedia article told as its life from idea to legacy, Where It Was Filmed, and links to read more.
- **Extras:** the bonus material in the film's folder.

Spoiler-safe (on by default): until a film is marked watched, review quotes and Behind the Film keep the story, twists and ending hidden, each with "Show anyway". Under the title, badges show the lists a film is on. A tag says whether to turn on HDR before Play. It's read from the file name, with your own setting for the file winning.

Trailers are the film's own trailers on YouTube, played inside Reel in YouTube's privacy-enhanced player. Films open in IINA, VLC or the default app. Back from the player, Reel asks "Did you finish it?" and then "How was it?".

## Recommended and For You

**Recommended:** five films from your library, picked fresh each launch, with mood chips. **For You:** films you don't have and haven't seen, which people who loved your favourites went on to love, with Because You Loved chips and New Picks.

## Explore

Trending This Week, then shelves that change each time Reel opens (Because You Loved, More from a director, a country's cinema, a decade or the hidden gems), and the **Best of** any year from the source you choose (Most Acclaimed, TMDB or IMDb rating, most popular, award winners, hidden gems). Mood chips narrow every row. Search finds any film. Not for Me keeps a film out of For You and Explore for good.

## New Releases

In Cinemas Now, Coming Soon, **New at Home** (recent cinema releases now out online in the US, from TMDB's digital release dates) and **New on Blu-ray** (TMDB's disc releases of the last three months, new films and new editions). Films you've seen are left out.

## Wishlist

Films you want and don't have yet. When one turns up on your drives, it leaves the wishlist on its own.

## Lists

Search for lists by any words: a theme, a series, a person, a country's cinema, a decade, Wikipedia's "List of … films", or one of Reel's own lists. Below it, four chapters, the last one open kept between launches:

- **Your Lists:** Start Here (the films the polls, festivals and rankings agree on that you haven't seen, those already on your drives and those worth finding), Your Progress, and Complete the Set (directors, cinematographers and franchises).
- **The Canon:** Sight and Sound's critics' and directors' polls, AFI's 100 and the Criterion Collection.
- **Festivals & Awards:** festivals, academy awards and cinematography awards, from Wikidata, refreshed weekly.
- **Rankings:** the year's and the decade's Most Acclaimed, and IMDb's Top 250, the Top 100 of any year or decade, the most voted, and the best of each genre.

An award list is added only when Wikidata records its winners for at least 80% of the award's years. 70–80% is shown with a note, and less is left out. Each list shows what you own and have seen.

## Year in Film

What you watched each year: films, hours, rewatches, month by month, highlights, your stars and film nights, and the genres, decades, people and lists that came up most.

## Cinema mode

⇧⌘C turns Reel into a view for the TV: full screen, big targets, and text of 22 points or more. Three tabs:

- **For You:** Tonight, Recommended for You, New Arrivals, Like the Films You Loved, the Watchlist, genres, languages, Under 100 Minutes, Acclaimed and Watch Again.
- **Tonight:** the shortlist with Decide for Us.
- **All Films:** with its filters and search.

The arrow keys reach everything. Return opens and plays, Space plays the trailer, T adds to or takes off Tonight, and Esc goes back. Turning it off returns the window exactly as it was.

## Background work

While Reel is open, everything from the web refreshes on its own, each item only when due: film info and ratings monthly, award lists weekly, sets every two weeks, IMDb's ratings and list posters monthly, Explore every six hours. Reel also picks up again when the network comes back or the Mac wakes. Left alone for an hour on CI after launch, Reel made no web request and no save.

## Where Reel keeps things

Everything is in `~/Documents/Reel/`:

| | |
|---|---|
| `Your Notes.json` | watched, favorites, watchlist, ratings, notes, wishlist, matches, frame removals, match and grouping fixes (irreplaceable; set aside, never overwritten, if unreadable) |
| `Settings.json` | TMDB token, OMDb key, drives and which one is the Backup, films marked Not for Me (mode 600) |
| `Library.json` | film info per file: a cache, rebuilt by a rescan (format 7) |
| `Safety Copies/` | one copy of Your Notes and one of Settings per day, the last 30 days |
| `Image Cache.nosync/` | posters and photos, capped at 400 MB |
| `List Data.nosync/` | IMDb ratings, award lists, list posters, critics' scores and sets (downloaded again if deleted) |

Writes are atomic, batched and run in the background; everything is flushed on quit. Network requests use no disk cache and no cookies. Nothing is ever written to film drives.

## Code

- `Sources/ReelCore`: logic with no UI: file-name reader, TMDB client, matcher, drive scanner and extras grouping, arrivals and the Backup check, your data (`UserData.swift`), reviews (`Reception.swift`), moods, recommendations, Year in Film, IMDb ratings, Wikidata lists and the bundled polls (`Lists.swift`), Most Acclaimed, film sets, library format and storage.
- `Sources/Reel/Model`: app state (`AppModel`, split by topic into `AppModel+….swift`), the lists store, image cache.
- `Sources/Reel/Views`: the desk (sidebar, grid in `LibraryGridView`, `LibraryFilters` and `PosterCard`, film page in `FilmPage` and `OverviewTab`); `Views/Cinema` is Cinema mode, a separate view tree.
- `Sources/Reel/Diagnostics`: the CI renderer (screens, smoothness and idle gates) and the scrolling counter.
- `Tests/ReelCoreTests`: run on every push.

## Builds and CI

Every push runs the core tests on Linux and builds the app on a Mac, timing the smoothness gates. A commit with `[build]` makes the signed `Reel-mac` download and pushes the screens (desk and Cinema mode at the laptop's size, 1080p and 4K) to the `screens` branch. A few jobs run only when named in a commit:

- `[review-check]` and `[review-eval]` read and check the Reviews gate, on public films.
- `[lists-check]` reads the new lists live.
- `[idle-check]` leaves Reel alone for an hour.

Builds carry no keys. The TMDB token and the OMDb key are pasted once in Reel and kept only in `Settings.json`. CI reads its own copies from the repository's secrets and never prints them. File names in the tests are made up, and the review fixtures are sentences from public reviews of well-known films.
