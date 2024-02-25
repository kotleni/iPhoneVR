//
//  cardboard_plus.h
//  sdk
//
//  Created by Viktor Varenik on 25.02.2024.
//

#ifndef cardboard_plus_h
#define cardboard_plus_h

#include "../lens_distortion.h"
#include "../distortion_renderer.h"
#include "../head_tracker.h"

struct CardboardLensDistortion : cardboard::LensDistortion {};
struct CardboardDistortionRenderer : cardboard::DistortionRenderer {};
struct CardboardHeadTracker : cardboard::HeadTracker {};

#endif /* cardboard_plus_h */
