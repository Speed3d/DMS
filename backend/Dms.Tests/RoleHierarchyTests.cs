using Dms.Domain;
using Xunit;

namespace Dms.Tests;

public class RoleHierarchyTests
{
    [Theory]
    [InlineData(UserRole.SuperAdmin, UserRole.President, true)]
    [InlineData(UserRole.President, UserRole.Manager, true)]
    [InlineData(UserRole.Manager, UserRole.Employee, true)]
    [InlineData(UserRole.Manager, UserRole.Reader, true)]
    public void CanManage_LowerLevels(UserRole actor, UserRole target, bool expected)
        => Assert.Equal(expected, RoleHierarchy.CanManage(actor, target));

    [Theory]
    [InlineData(UserRole.Manager, UserRole.Manager)]   // نفس المستوى
    [InlineData(UserRole.Manager, UserRole.President)]  // أعلى
    [InlineData(UserRole.Employee, UserRole.Manager)]   // أعلى
    [InlineData(UserRole.Reader, UserRole.Reader)]
    public void CannotManage_SameOrHigher(UserRole actor, UserRole target)
        => Assert.False(RoleHierarchy.CanManage(actor, target));

    [Theory]
    [InlineData(UserRole.SuperAdmin, true)]
    [InlineData(UserRole.President, true)]
    [InlineData(UserRole.Manager, true)]
    [InlineData(UserRole.Employee, false)]
    [InlineData(UserRole.Reader, false)]
    public void IsManagerOrAbove(UserRole role, bool expected)
        => Assert.Equal(expected, RoleHierarchy.IsManagerOrAbove(role));

    [Theory]
    [InlineData(UserRole.SuperAdmin, true)]
    [InlineData(UserRole.President, true)]
    [InlineData(UserRole.Manager, false)]
    [InlineData(UserRole.Employee, false)]
    public void IsPresidentOrAbove(UserRole role, bool expected)
        => Assert.Equal(expected, RoleHierarchy.IsPresidentOrAbove(role));
}
