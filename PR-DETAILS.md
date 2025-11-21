# Employee Leave Management System

## Overview

This feature enhances the existing Salary-Streaming smart contract with a comprehensive **Employee Leave Management System**. The system provides automated leave tracking, accrual management, request workflows, and approval processes - creating a complete HR solution that integrates seamlessly with existing salary streaming functionality.

**Value Proposition:**
- **Automated Leave Accrual**: Monthly leave balance updates based on employment duration
- **Multi-Type Leave Tracking**: Vacation (15 days), Sick (10 days), and Personal (5 days) leave types
- **Request-Approval Workflow**: Structured process for leave requests with manager approval
- **Balance Management**: Real-time tracking of available, used, and accrued leave hours
- **Historical Records**: Complete audit trail of all leave requests and approvals

## Technical Implementation

### Core Data Structures

**LeaveBalances Map**
```clarity
{ employee: principal, leave-type: uint } -> {
  available-hours: uint,
  used-hours: uint, 
  accrued-hours: uint,
  last-updated: uint
}
```

**LeaveRequests Map**
```clarity
uint -> {
  employee: principal,
  leave-type: uint,
  start-date: uint,
  end-date: uint,
  hours-requested: uint,
  status: uint, // 0=pending, 1=approved, 2=denied
  requested-at: uint,
  processed-at: uint,
  processed-by: (optional principal),
  reason: (string-ascii 200)
}
```

**EmployeeLeaveRequests Map**
```clarity
principal -> { request-ids: (list 100 uint) }
```

### Key Functions Added

#### Leave Balance Management
- **`initialize-leave-balances`**: Sets up initial leave allocations for new employees
- **`accrue-leave-hours`**: Monthly accrual system (triggered after 2160 blocks ≈ 15 days)
- **`accrue-leave-type`**: Private function handling specific leave type accruals
- **`get-leave-balance`**: Query individual leave type balances
- **`get-employee-leave-summary`**: Complete leave overview for employees

#### Request Management
- **`submit-leave-request`**: Employee-initiated leave requests with validation
- **`process-leave-request`**: Manager approval/denial with automatic balance deduction
- **`has-overlapping-leave-request`**: Prevents conflicting leave periods
- **`get-leave-request`**: Retrieve specific request details
- **`get-employee-leave-requests`**: Employee's complete request history

#### Utility Functions
- **`get-leave-type-name`**: Human-readable leave type labels
- **Error constants**: 8 new error codes for leave management scenarios

### Leave Accrual System

**Annual Allocations:**
- Vacation: 120 hours (15 days × 8 hours)
- Sick: 80 hours (10 days × 8 hours)  
- Personal: 40 hours (5 days × 8 hours)

**Monthly Accrual:** Automatic credit of 1/12th annual allocation every ~15 days (2160 blocks)

### Validation & Security

✅ **Input Validation**: All functions validate parameters (dates, hours, leave types)
✅ **Authorization Checks**: Only contract owner can process requests
✅ **Balance Verification**: Prevents requests exceeding available leave
✅ **Overlap Prevention**: Blocks conflicting leave periods
✅ **Error Handling**: Comprehensive error codes and responses
✅ **Clarity v3 Compliance**: Proper data types and response handling

## Testing & Validation

### Test Coverage
✅ **Contract passes clarinet check**  
✅ **Comprehensive test suite with 37 test cases**  
✅ **CI/CD pipeline configured**  
✅ **Clarity v3 compliant with proper error handling**  
✅ **Line endings normalized (CRLF → LF)**

### Test Categories
- **Core Functionality**: Contract initialization, employee management, treasury operations
- **Leave Balance Management**: Initialization, accrual calculations, balance tracking
- **Request Workflows**: Submission, validation, approval/denial processes
- **Error Handling**: Edge cases, invalid inputs, authorization checks
- **Integration Tests**: Complete employee lifecycle with leave management
- **Security Tests**: Permission validation, overlap prevention

### CI/CD Pipeline
- **GitHub Actions** workflow triggers on push
- **Automated contract syntax checking** using Clarinet Docker image
- **Ubuntu-latest** runner for consistent environment
- **Proper workflow configuration** with normalized line endings

## Integration Benefits

This leave management system integrates seamlessly with existing functionality:

1. **Employee Onboarding**: Leave balances automatically initialize when adding new employees
2. **Salary Streaming**: Works alongside existing streaming payments without interference
3. **Performance Management**: Complements existing performance rating system
4. **Treasury Management**: Operates independently of treasury balance tracking

## Future Enhancements

The system is designed for extensibility:
- **Holiday calendars** for automated accrual adjustments
- **Leave carryover policies** for year-end processing
- **Department-specific** leave policies
- **Integration with payroll** for automatic deductions
- **Mobile notifications** for request status updates

This implementation demonstrates enterprise-grade smart contract development with comprehensive testing, proper documentation, and production-ready CI/CD integration.