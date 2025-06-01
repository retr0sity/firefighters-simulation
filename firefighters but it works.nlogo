globals [
  base-x base-y
  wind-direction    ; 0=no wind, 1=north, 2=east, 3=south, 4=west
  total-trees
  trees-burned
  trees-saved
  fires-detected
  water-used
  simulation-time
  simulation-ended?  ; New variable to track if simulation has ended
]

breed [scouters scouter]
breed [ground-units ground-unit]
breed [trees tree]
breed [fires fire]

scouters-own [
  detection-radius
  speed
  target-fire
  patrolling?
]

ground-units-own [
  water-capacity
  current-water
  speed
  target-fire
  returning-to-base?
  extinguishing?
]

trees-own [
  tree-state        ; 0=healthy, 1=burning, 2=burning-long, 3=extinguished, 4=burned-out
  burn-time
  max-burn-time
]

fires-own [
  intensity
  spread-timer
  detected?
]

patches-own [
  is-base?
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SETUP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to setup
  clear-all

  ; Initialize globals
  set base-x 0
  set base-y 0
  set total-trees 0
  set trees-burned 0
  set trees-saved 0
  set fires-detected 0
  set water-used 0
  set simulation-time 0
  set simulation-ended? false  ; Initialize simulation state

  ; Set wind direction (assumed wind-setting is a slider or input)
  set wind-direction wind-setting

  ; Create base at center
  ask patch base-x base-y [
    set pcolor brown
    set is-base? true
  ]

  ; Generate forest
  generate-forest

  ; Create scouters
  create-scouters num-scouters [
    set color blue
    set size 1.5
    set shape "person"  ; Changed shape to represent human scouts
    set detection-radius scouter-detection-radius
    set speed scouter-speed
    set patrolling? true
    set target-fire nobody

    ; Position randomly but not on base
    let valid-position false
    while [not valid-position] [
      setxy random-xcor random-ycor
      if distance patch base-x base-y > 2 [
        set valid-position true
      ]
    ]
  ]

  ; Create ground units
  create-ground-units num-ground-units [
    set color red
    set size 2
    set shape "truck"  ; Changed shape to distinguish from trees
    set water-capacity max-water-capacity
    set current-water max-water-capacity
    set speed ground-unit-speed
    set returning-to-base? false
    set extinguishing? false
    set target-fire nobody

    ; Start at base
    setxy base-x base-y
  ]

  ; Start initial fires if requested
  if initial-fires > 0 [
    repeat initial-fires [
      start-random-fire
    ]
  ]

  reset-ticks
end

;; Add this function to your code
to cleanup-orphaned-fires
  ;; Remove fire markers that no longer have burning trees
  ask fires [
    let fire-patch patch-here
    let has-burning-trees false
    ask fire-patch [
      if any? trees-here with [tree-state = 1 or tree-state = 2] [
        set has-burning-trees true
      ]
    ]
    if not has-burning-trees [
      ;; Clear this fire from any ground units targeting it
      ask ground-units with [target-fire = myself] [
        set target-fire nobody
        set extinguishing? false
      ]
      die  ;; Remove the fire marker
    ]
  ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GENERATE FOREST
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to generate-forest
  ask patches [
    if random 100 < forest-density and (is-base? != false) [
      sprout-trees 1 [
        set color green
        set size 1.2  ; Made trees slightly larger
        set shape "tree"  ; Set tree shape to built-in tree shape
        set tree-state 0
        set burn-time 0
        set max-burn-time burn-duration
        set total-trees total-trees + 1
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; GO
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to go
  ; Check if simulation should end
  if check-simulation-end [
    stop  ; This will end the simulation
  ]

  if not any? fires and not any? trees with [tree-state = 1 or tree-state = 2] [
    if auto-start-fires [
      ;; Randomly start new fires
      if random 1000 < fire-start-probability * 10 [
        start-random-fire
      ]
    ]
  ]

  ;; Update simulation time
  set simulation-time simulation-time + 1

  ;; Agent behaviors
  ask scouters [ scouter-behavior ]
  ask ground-units [ ground-unit-behavior ]

  ;; Fire dynamics
  ask trees with [ tree-state = 1 or tree-state = 2 ] [ update-fire ]
  spread-fires

  cleanup-orphaned-fires

  ;; Update displays
  update-tree-colors
  update-info-display

  tick
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CHECK SIMULATION END
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to-report check-simulation-end
  ; Check if there are no burning trees (state 1 or 2)
  let burning-trees count trees with [tree-state = 1 or tree-state = 2]

  ; End simulation when no trees are burning, regardless of fire markers or auto-start setting
  if burning-trees = 0 and not simulation-ended? [
    set simulation-ended? true

    ; Clean up any remaining fire markers
    ask fires [ die ]

    ; Calculate final statistics
    let healthy-trees count trees with [tree-state = 0 or tree-state = 3]
    let total-burned count trees with [tree-state = 4]
    let survival-rate 0

    if total-trees > 0 [
      set survival-rate (healthy-trees / total-trees) * 100
    ]

    ; Display end message
    user-message (word "SIMULATION ENDED!\n\n"
                      "Final Statistics:\n"
                      "Total Trees: " total-trees "\n"
                      "Trees Burned: " total-burned "\n"
                      "Trees Saved/Healthy: " healthy-trees "\n"
                      "Tree Survival Rate: " precision survival-rate 1 "%\n"
                      "Fires Detected: " fires-detected "\n"
                      "Water Used: " water-used " units\n"
                      "Simulation Time: " simulation-time " ticks\n\n"
                      "All fires have been extinguished or burned out!")

    report true
  ]

  report false
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; IMPROVED GROUND-UNIT BEHAVIOR
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; IMPROVED GROUND-UNIT BEHAVIOR - FOCUSED TREE TARGETING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to ground-unit-behavior
  ;; 1) If out of water, head back to base (but remember our fire location)
  if current-water <= 0 and not returning-to-base? [
    set returning-to-base? true
    set extinguishing? false
    ;; Keep target-fire so we can return to it after refilling
  ]

  ;; 2) RETURN-TO-BASE behavior
  if returning-to-base? [
    face patch base-x base-y
    forward speed

    ;; Refill at base
    if distance patch base-x base-y < 1.5 [
      set current-water water-capacity
      set returning-to-base? false
      ;; Don't clear target-fire - we'll return to finish the job
    ]
    stop
  ]

  ;; 3) If we have a fire to fight, work on it systematically
  ifelse target-fire != nobody [
    ;; Check if our target fire still exists
    ifelse member? target-fire fires [
      ;; Check if there are still burning trees at target location
      let target-patch [patch-here] of target-fire
      let burning-trees-at-target nobody
      ask target-patch [
        set burning-trees-at-target trees-here with [tree-state = 1 or tree-state = 2]
      ]

      ifelse any? burning-trees-at-target [
        ;; Move to the fire location first
        face target-fire
        let dist distance target-fire

        ;; If close enough to work on the fire
        ifelse dist <= 1.5 [
          set extinguishing? true

          if current-water > 0 [
            ;; FOCUS: Find the closest burning tree to our current position
            let closest-burning-tree min-one-of burning-trees-at-target [distance myself]

            if closest-burning-tree != nobody [
              ;; Move towards the closest burning tree if we're not right next to it
              let tree-distance distance closest-burning-tree
              if tree-distance > 0.5 [
                face closest-burning-tree
                forward min(list speed tree-distance)
              ]

              ;; Extinguish the closest tree if we're close enough
              if tree-distance <= 1.0 [
                ask closest-burning-tree [
                  set tree-state 3  ;; extinguished
                  set trees-saved trees-saved + 1
                ]
                set current-water current-water - 1
                set water-used water-used + 1
              ]
            ]
          ]
        ] [
          ;; Move toward the fire location
          forward speed
        ]
      ] [
        ;; No more burning trees at this location - fire is completely out
        ask target-fire [ die ]  ;; Remove fire marker
        set target-fire nobody
        set extinguishing? false
      ]
    ] [
      ;; Target fire no longer exists - clear target
      set target-fire nobody
      set extinguishing? false
    ]

  ] [
    ;; 4) Look for new fires only if we don't have a target
    let available-fires fires with [
      ;; Only target fires that actually have burning trees
      any? [trees-here with [tree-state = 1 or tree-state = 2]] of patch-here
    ]

    ifelse any? available-fires [
      ;; Pick the closest fire and COMMIT to it
      set target-fire min-one-of available-fires [distance myself]
    ] [
      ;; No fires available - return to base
      face patch base-x base-y
      let dist-to-base distance patch base-x base-y
      if dist-to-base > 1.5 [
        forward speed
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; IMPROVED SCOUTER BEHAVIOR (better fire detection)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to scouter-behavior
  ;; Check for fires in detection radius
  let nearby-burning-trees trees with [ tree-state = 1 or tree-state = 2 ] in-radius detection-radius

  ;; If burning trees detected and not already targeting a fire here
  if any? nearby-burning-trees and target-fire = nobody [
    let burning-tree one-of nearby-burning-trees
    let fire-location [patch-here] of burning-tree

    ;; Check if there's already a fire marker at this location
    let existing-fire one-of fires-on fire-location

    ifelse existing-fire != nobody [
      set target-fire existing-fire
    ] [
      ;; Create new fire marker
      let new-fire nobody
      ask fire-location [
        sprout-fires 1 [
          set color orange
          set size 1.0
          set shape "circle"  ; Changed to circle shape for fire detection marker
          set intensity 1
          set detected? true
          set fires-detected fires-detected + 1
          set new-fire self  ;; store reference to this new fire
        ]
      ]
      ;; Set the new fire as target
      set target-fire new-fire
    ]

    set patrolling? false

    ;; Alert available ground units
    ask ground-units with [target-fire = nobody and not returning-to-base?] [
      set target-fire [target-fire] of myself
    ]
  ]

  ;; Movement behavior
  ifelse patrolling? [
    ;; Random patrol movement
    rt (random 60) - 30
    forward speed

    ;; Avoid edges
    if abs xcor > world-width / 2 - 2 or abs ycor > world-height / 2 - 2 [
      face patch 0 0
    ]
  ] [
    ;; Monitor target fire
    if target-fire != nobody [
      let target-patch [patch-here] of target-fire
      let still-burning? false
      ask target-patch [
        if any? trees-here with [tree-state = 1 or tree-state = 2] [
          set still-burning? true
        ]
      ]

      ifelse still-burning? [
        ;; Stay near the fire to monitor
        face target-fire
        if distance target-fire > 2 [
          forward speed
        ]
      ] [
        ;; Fire is out, resume patrolling
        set target-fire nobody
        set patrolling? true
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; UPDATE FIRE (unchanged)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to update-fire
  set burn-time burn-time + 1

  ;; Transition from burning to burning-long
  if burn-time >= max-burn-time / 2 and tree-state = 1 [
    set tree-state 2
  ]

  ;; Tree burns out completely
  if burn-time >= max-burn-time [
    set tree-state 4
    set trees-burned trees-burned + 1
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; SPREAD FIRES (unchanged as far as patch-ahead)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to spread-fires
  ask trees with [ tree-state = 1 or tree-state = 2 ] [
    if random 100 < fire-spread-rate [
      let spread-candidates neighbors with [ any? trees-here with [ tree-state = 0 ] ]

      ;; Apply wind effects
      if wind-direction != 0 [
        if wind-direction = 1 [ ;; North wind
          set spread-candidates spread-candidates with [ pycor > [ pycor ] of myself ]
        ]
        if wind-direction = 2 [ ;; East wind
          set spread-candidates spread-candidates with [ pxcor > [ pxcor ] of myself ]
        ]
        if wind-direction = 3 [ ;; South wind
          set spread-candidates spread-candidates with [ pycor < [ pycor ] of myself ]
        ]
        if wind-direction = 4 [ ;; West wind
          set spread-candidates spread-candidates with [ pxcor < [ pxcor ] of myself ]
        ]
      ]

      if any? spread-candidates [
        ask one-of spread-candidates [
          ask trees-here with [ tree-state = 0 ] [
            set tree-state 1
            set burn-time 0
          ]
        ]
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; START RANDOM FIRE (updated to not create fire agents automatically)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to start-random-fire
  let potential-trees trees with [ tree-state = 0 ]
  if any? potential-trees [
    ask one-of potential-trees [
      set tree-state 1
      set burn-time 0
      ; Fire agents are now only created when detected by scouters
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; UPDATE TREE COLORS (unchanged)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to update-tree-colors
  ask trees [
    if tree-state = 0 [ set color green ]
    if tree-state = 1 [ set color red ]
    if tree-state = 2 [ set color red - 2 ]  ;; dark red
    if tree-state = 3 [ set color yellow ]
    if tree-state = 4 [ set color black ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; UPDATE INFO DISPLAY (stub)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to update-info-display

end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MANUAL FIRE STARTING (updated to not create fire agents automatically)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to start-fire-at-mouse
  if mouse-down? [
    ask patch mouse-xcor mouse-ycor [
      if any? trees-here with [ tree-state = 0 ] [
        ask trees-here with [ tree-state = 0 ] [
          set tree-state 1
          set burn-time 0
          ; Fire agents are now only created when detected by scouters
        ]
      ]
    ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; REPORTS (unchanged)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
to-report fire-efficiency
  if fires-detected > 0 [
    report trees-saved / fires-detected
  ]
  report 0
end

to-report area-coverage
  let scouter-coverage 0
  ask scouters [
    set scouter-coverage scouter-coverage + (detection-radius * detection-radius * 3.14159)
  ]
  let total-area world-width * world-height
  report (scouter-coverage / total-area) * 100
end

to-report average-response-time
  let total-distance 0
  let fire-count 0
  ask fires [
    let nearest-unit min-one-of ground-units [ distance myself ]
    if nearest-unit != nobody [
      set total-distance total-distance + distance nearest-unit
      set fire-count fire-count + 1
    ]
  ]
  if fire-count > 0 [
    report total-distance / fire-count
  ]
  report 0
end
@#$#@#$#@
GRAPHICS-WINDOW
210
10
647
448
-1
-1
13.0
1
10
1
1
1
0
1
1
1
-16
16
-16
16
0
0
1
ticks
30.0

CHOOSER
22
22
160
67
wind-setting
wind-setting
0 "north" "south" "east" "west"
0

SLIDER
25
102
197
135
num-scouters
num-scouters
0
50
6.0
1
1
NIL
HORIZONTAL

SLIDER
28
150
214
183
scouter-detection-radius
scouter-detection-radius
0
100
60.0
1
1
NIL
HORIZONTAL

SLIDER
32
194
204
227
scouter-speed
scouter-speed
0
10
5.0
1
1
NIL
HORIZONTAL

SLIDER
39
284
211
317
num-ground-units
num-ground-units
0
50
4.0
1
1
NIL
HORIZONTAL

SLIDER
39
337
211
370
max-water-capacity
max-water-capacity
0
40
12.0
1
1
NIL
HORIZONTAL

SLIDER
41
391
213
424
ground-unit-speed
ground-unit-speed
0
1
1.0
0.1
1
NIL
HORIZONTAL

SLIDER
38
432
210
465
initial-fires
initial-fires
0
100
25.0
1
1
NIL
HORIZONTAL

SLIDER
39
241
211
274
forest-density
forest-density
0
100
40.0
1
1
NIL
HORIZONTAL

SLIDER
45
498
217
531
forest-duration
forest-duration
0
100
89.0
1
1
NIL
HORIZONTAL

SLIDER
51
558
223
591
burn-duration
burn-duration
0
100
43.0
1
1
NIL
HORIZONTAL

SLIDER
53
678
225
711
fire-start-probability
fire-start-probability
0
100
10.0
1
1
NIL
HORIZONTAL

SLIDER
293
557
465
590
fire-spread-rate
fire-spread-rate
0
4
3.3
0.1
1
NIL
HORIZONTAL

SWITCH
87
603
228
636
auto-start-fires
auto-start-fires
0
1
-1000

BUTTON
246
460
309
493
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
325
460
388
493
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
686
19
822
64
ticks prosomoiwshs
simulation-time
17
1
11

PLOT
687
89
887
239
Dentra
Ticks
Trees
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -10899396 true "" "plot count trees with [tree-state = 0]"
"pen-1" 1.0 0 -2674135 true "" "plot count trees with [tree-state = 1 or tree-state = 2]"
"pen-2" 1.0 0 -1184463 true "" "plot count trees with [tree-state = 3]"
"pen-3" 1.0 0 -16777216 true "" "plot count trees with [tree-state = 4]"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
