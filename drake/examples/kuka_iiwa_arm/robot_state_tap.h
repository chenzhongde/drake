#pragma once

#include "drake/core/Vector.h"

namespace drake {

/// Implements a Drake System (@see drake/systems/System.h) that
/// saves the latest system state as a local variable and provides an accessor
/// to it. This is useful for testing the final state of the robot in a unit
/// test. It otherwise merely passes through its input to output.
template <template <typename> class Vector>
class RobotStateTap {
 public:
  /// Create an RobotStateTap that publishes on the given @p lcm instance.
  explicit RobotStateTap() {}

  // Noncopyable.
  RobotStateTap(const RobotStateTap&) = delete;
  RobotStateTap& operator=(const RobotStateTap&) = delete;

  /// @name Implement the Drake System concept.
  //@{

  template <typename ScalarType>
  using StateVector = Drake::NullVector<ScalarType>;
  template <typename ScalarType>
  using InputVector = Vector<ScalarType>;
  template <typename ScalarType>
  using OutputVector = Vector<ScalarType>;

  StateVector<double> dynamics(const double& t, const StateVector<double>& x,
                               const InputVector<double>& u) const {
    return StateVector<double>();
  }

  OutputVector<double> output(const double& t, const StateVector<double>& x,
                              const InputVector<double>& u) {
    if (u_.size() != u.size())
      u_.resize(u.size());

    for (int ii = 0; ii < u.size(); ++ii) {
      u_[ii] = u[ii];
    }

    return u;
  }

  bool isTimeVarying() const { return false; }
  bool isDirectFeedthrough() const { return true; }

  const InputVector<double>& get_input_vector() { return u_; }

  //@}

 private:
  InputVector<double> u_;
};

}  // namespace drake
