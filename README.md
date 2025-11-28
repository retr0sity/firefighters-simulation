# Forest Fire Detection & Suppression Simulation

A NetLogo-based simulation modeling an autonomous forest fire detection and suppression system using coordinated emergency response teams.

## Overview

This simulation demonstrates how coordinated emergency teams can detect fires early and suppress them before they spread extensively through a forest. The model features autonomous scouting units that patrol and detect fires, and ground firefighting units that respond to extinguish them.

## Features

- **Scouter Units (Blue)**: Autonomous patrol units that detect fires within their detection radius
- **Ground Units (Red trucks)**: Firefighting vehicles that extinguish fires using water
- **Dynamic Fire Spread**: Fire spreads to neighboring trees based on spread rate and wind conditions
- **Resource Management**: Ground units must return to base to refill water
- **Real-time Statistics**: Track trees saved, burned, water used, and response times
- **Wind Effects**: Configurable wind direction affects fire spread patterns

## Tree States

- 🟢 **Green**: Healthy, unburned trees
- 🔴 **Red**: Trees that just caught fire
- 🔴 **Dark Red**: Trees burning for extended time
- 🟡 **Yellow**: Trees saved by firefighting efforts
- ⚫ **Black**: Trees completely destroyed by fire

## Parameters

### Forest Parameters
- `forest-density`: Percentage of patches containing trees (0-100%)
- `burn-duration`: How long trees burn before being destroyed

### Fire Parameters
- `initial-fires`: Number of fires to start the simulation
- `fire-spread-rate`: Probability of fire spreading to neighboring trees (0-4)
- `auto-start-fires`: Whether new fires start automatically during simulation
- `fire-start-probability`: Probability of new fires starting
- `wind-setting`: Wind direction (none/north/south/east/west)

### Scouter Parameters
- `num-scouters`: Number of detection units
- `scouter-detection-radius`: How far scouters can detect fires
- `scouter-speed`: Movement speed of scouters

### Ground Unit Parameters
- `num-ground-units`: Number of firefighting vehicles
- `max-water-capacity`: Water capacity per ground unit
- `ground-unit-speed`: Movement speed of ground units

## How to Run

1. **Install NetLogo**: Download from [NetLogo website](https://ccl.northwestern.edu/netlogo/)
2. **Open the model**: Load `forest-fire-simulation.nlogo`
3. **Adjust parameters**: Use the sliders to configure your simulation
4. **Setup**: Click "Setup" to initialize
5. **Run**: Click "Go" to start the simulation

## How It Works

1. **Detection Phase**: Scouter units patrol the forest and detect fires, creating fire markers
2. **Response Phase**: Ground units respond to detected fires
3. **Suppression Phase**: Ground units extinguish burning trees using water
4. **Spread Phase**: Uncontrolled fires continue spreading to neighboring trees
5. **Recovery Phase**: Units return to base for refueling when needed

## Statistics & Metrics

The simulation tracks:
- Total trees vs trees burned/saved
- Survival rate (percentage of forest saved)
- Fires detected
- Water used
- Average response time
- Fire efficiency (trees saved per fire detected)

## Technologies

- **NetLogo 6.4.0**: Agent-based modeling platform
- **Multi-agent system**: Different agent types with unique behaviors
- **Dynamic simulation**: Real-time state changes and visual feedback

## Author

Ioannis Karkalas

## License

[Your chosen license - e.g., MIT]
