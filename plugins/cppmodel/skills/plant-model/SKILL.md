---
name: cppmodel:plant-model
description: Build a minimal plant model (the simulated physical mechanism) for a new CppModel simulation, and scaffold a starter simulation file wiring it to the controller under test. Use when a customer needs to simulate a new physical mechanism (actuator, motor, sensor pair) that has no model yet.
---

## Scope: this builds the plant side

This skill assumes the **plant** is the component being simulated and the **controller** is the
real code under test - see `cppmodel:simulation-testing`'s "which side is being simulated" note.
Concretely: the model's `actuators` struct is what the controller commands into it (read via
`CppModel_getInput*` in the simulation file), and its `sensors` struct is what it reports back to
the controller (published via `CppModel_setOutput*`). If instead the controller is the side being
simulated and the plant is real/external, this skill's shape doesn't apply as-is - the roles invert.

## What this produces

1. A model - wherever this project keeps its models. Don't assume a path; ask, or look for an
   existing `models/` folder near the other simulations first. Shape depends on the language (see
   below):
   - **C**: a `.h`/`.c` pair (naming convention: `<name>Model.h` / `<name>Model.c`).
   - **C++**: usually a single header-only `<Name>Model.h` with inline methods (this is the shape
     already-existing C++ models in this kind of project tend to use), unless the project's own
     convention already splits declaration/definition into a `.h`/`.cpp` pair - check first.
2. A starter simulation file skeleton wiring the new model's actuators/sensors to the controller
   under test, with no real test scenarios yet - hand off to the `cppmodel:simulation-testing`
   skill to fill those in and to know how that skeleton should be shaped for this project.

## Language: C or C++

Use the `cppmodel:language` skill to decide before writing anything below - it covers checking for
a stored project preference, detecting the project's existing convention, and asking/storing the
answer.

## Questions to ask first

Don't guess these - ask, since they determine the model's shape:

1. **What kind of mechanism is it?** In particular: does it travel between two end-stops (a
   cylinder, a lift, a gate - bounded 0..max), or does it move past repeating positions
   continuously (a rotating disc, an indexing wheel, a conveyor - unbounded, wraps around)? This
   decides which of the two shapes below to use.
2. **What does the controller command (actuators)?** Usually one or more booleans (e.g.
   `motor_up`/`motor_down`, `valve_open`) or a signed speed/PWM value. Match whatever the real
   controller code already outputs - look at its `outputs` struct.
3. **What does the controller read back (sensors)?** Booleans from limit/proximity switches,
   a position/pulse counter, a pressure or photocell reading. Match the controller's `inputs`
   struct.
4. **Timing**: how long does a full traverse take in the real machine (e.g. "fully extends in
   about 2 seconds")? Different speeds for different directions/actuators? What `task_period_ms`
   will the simulation run at (existing simulations in this project are usually 1ms - check one)?
5. **Limits and thresholds**: the position range (0..max, or the repeat period for a wraparound
   mechanism), and at what position(s) each sensor should read true.

## Two shapes, pick one and adapt

Each is shown in both languages - use whichever the `cppmodel:language` step decided.

**Bounded, end-stop mechanism** (e.g. a ladder/lift/cylinder):

```c
typedef struct <Name>ModelActuators_s { bool <direction_a>; bool <direction_b>; } <Name>ModelActuators_t;
typedef struct <Name>ModelSensors_s { bool <sensor_name>; } <Name>ModelSensors_t;
typedef struct <Name>ModelConfig_s
{
    uint32 delta_a;
    uint32 delta_b;
    uint32 max_position;
    uint32 sensor_active_position;
} <Name>ModelConfig_t;
typedef struct <Name>Model_s
{
    <Name>ModelConfig_t config;
    <Name>ModelActuators_t actuators;
    <Name>ModelSensors_t sensors;
    sint32 position;
    bool is_moving_up;
    bool is_moving_down;
} <Name>Model_t;

void <name>ModelCyclic(<Name>Model_t *const context, const unsigned long currentTime)
{
    const sint32 previousPosition = context->position;
    if (context->actuators.<direction_a>)
    {
        context->position += context->config.delta_a;
        if (context->position >= context->config.max_position) { context->position = context->config.max_position; }
    }
    else if (context->actuators.<direction_b>)
    {
        context->position -= context->config.delta_b;
        if (context->position <= 0) { context->position = 0; }
    }
    context->sensors.<sensor_name> = context->position >= context->config.sensor_active_position;
    context->is_moving_up = context->position > previousPosition;
    context->is_moving_down = context->position < previousPosition;
}
```

C++ equivalent - a class over `CppModelBase::Model` (`cppmodel/Model.h`), plain public members
instead of separate actuators/sensors/config structs (this is the shape an already-existing C++
model in this kind of project is likely to use - check one if present and match it instead of this
exactly):

```cpp
#include <cppmodel/Model.h>

class <Name>Model : public CppModelBase::Model
{
public:
    // actuators - commanded by the controller
    bool <direction_a> = false;
    bool <direction_b> = false;
    // sensors - reported back to the controller
    bool <sensor_name> = false;

    sint32 position = 0;
    bool is_moving_up = false;
    bool is_moving_down = false;

    uint32 delta_a = 0;
    uint32 delta_b = 0;
    uint32 max_position = 0;
    uint32 sensor_active_position = 0;

    inline <Name>Model() {}

    inline void RunCyclic(double stepTime) override
    {
        const sint32 previousPosition = position;
        if (<direction_a>)
        {
            position += delta_a;
            if (position >= max_position) { position = max_position; }
        }
        else if (<direction_b>)
        {
            position -= delta_b;
            if (position <= 0) { position = 0; }
        }
        <sensor_name> = position >= sensor_active_position;
        is_moving_up = position > previousPosition;
        is_moving_down = position < previousPosition;
    }
};
```

Unlike the C shape, nothing here goes through `CppModel_getInput*`/`setOutput*` - the simulation
file just instantiates this class as a member and reads/writes its public fields directly each
step (see `cppmodel:simulation-testing`).

**Unbounded, indexed/rotating mechanism** (e.g. a feed wheel, a conveyor with repeating slots):

```c
typedef struct <Name>ModelConfig_s
{
    double sensor_ratio;
    bool negativeDirection;
} <Name>ModelConfig_t;
typedef struct <Name>Model_s
{
    <Name>ModelActuators_t actuators;
    <Name>ModelSensors_t sensors;
    <Name>ModelConfig_t config;
    double precise_position;
    sint32 position;
    bool is_moving;
} <Name>Model_t;

void <name>ModelCyclic(<Name>Model_t *const context, const unsigned long currentTime)
{
    context->precise_position += (double)context->actuators.<speed_command> * context->config.sensor_ratio * (context->config.negativeDirection ? -1 : 1);
    context->position = (sint32)context->precise_position;
    context->is_moving = context->actuators.<speed_command> != 0;
    context->sensors.<sensor_name> = context->position % <repeat_period> < <window> || context->position % <repeat_period> > <repeat_period - window>;
}
```

The `double precise_position` accumulator matters: truncating straight to an integer position each
cycle loses fractional motion at low speeds and the position never advances. Always reset both
`position` and `precise_position` together in any init/reset path.

C++ equivalent:

```cpp
#include <cppmodel/Model.h>

class <Name>Model : public CppModelBase::Model
{
public:
    <ActuatorType> <speed_command> = 0;
    bool <sensor_name> = false;

    double sensor_ratio = 0.;
    bool negativeDirection = false;

    double precise_position = 0.;
    sint32 position = 0;
    bool is_moving = false;

    inline <Name>Model() {}

    inline void RunCyclic(double stepTime) override
    {
        precise_position += (double)<speed_command> * sensor_ratio * (negativeDirection ? -1 : 1);
        position = (sint32)precise_position;
        is_moving = <speed_command> != 0;
        <sensor_name> = position % <repeat_period> < <window> || position % <repeat_period> > <repeat_period - window>;
    }
};
```

## Converting real-world timing into a delta-per-cycle

The model has no notion of seconds or physical units - only "how much does position change per
simulated cycle". Derive it:

```
delta_per_cycle = full_range_units / (traverse_time_ms / task_period_ms)
```

Example: a cylinder spans 0..1000 and fully extends in 2000ms, simulated at `task_period_ms = 1`:
`delta_per_cycle = 1000 / (2000 / 1) = 0.5` per cycle (round/adjust for integer config types).

## Keep it minimal

The goal is the least logic that reproduces control-relevant behavior - not a physically accurate
plant. No differential equations, no inertia/friction/acceleration curves, no plant-side PID, no
SI units. If a customer's description implies one of those, don't refuse it outright - ask whether
a simpler delta/threshold version would already exercise the controller correctly, and build that
instead unless they confirm the extra complexity is actually needed.

## Next step

Once the model and starter simulation exist, use the `cppmodel:simulation-testing` skill to add
real test scenarios and assertions.
