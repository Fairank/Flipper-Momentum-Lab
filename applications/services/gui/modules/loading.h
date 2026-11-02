#pragma once
#include <gui/view.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Loading anonymous structure */
typedef struct Loading Loading;

/** Allocate and initialize
 *
 * This View used to show system is doing some processing
 *
 * @return     Loading View instance
 */
Loading* loading_alloc(void);

/** Deinitialize and free Loading View
 *
 * @param      instance  Loading instance
 */
void loading_free(Loading* instance);

/** Get Loading view
 *
 * @param      instance  Loading instance
 *
 * @return     View instance that can be used for embedding
 */
View* loading_get_view(Loading* instance);

/** Show how far along the work is, under the animation (or the text, if set)
 *
 * For work whose length is known up front and long enough that a spinner alone
 * leaves the user unsure anything is happening. The animation keeps running: the
 * bar says how much is left, the animation says the system is still alive.
 *
 * @param      instance  Loading instance
 * @param      progress  Fraction done, 0.0f to 1.0f, clamped
 */
void loading_set_progress(Loading* instance, float progress);

/** Hide the progress bar
 *
 * Text set with loading_set_text() stays.
 *
 * @param      instance  Loading instance
 */
void loading_reset_progress(Loading* instance);

/** Name the work in progress next to the animation
 *
 * With text, the animation moves to the left and the text, bold and centered,
 * takes the space to its right; a progress bar then sits under the text. Room is
 * two lines of about 15 Latin characters, fewer CJK: a longer line wraps within
 * that space, and a third line runs into the bar. The text stays until changed
 * and does not touch the progress bar. It is copied, so the caller may reuse or
 * free its buffer right away; setting the text already shown does not redraw.
 *
 * @param      instance  Loading instance
 * @param      text      Text to show, "\n" starts the second line. NULL or ""
 *                       goes back to the centered animation.
 */
void loading_set_text(Loading* instance, const char* text);

#ifdef __cplusplus
}
#endif
