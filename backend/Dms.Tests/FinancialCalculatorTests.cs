using Dms.Domain;
using Xunit;

namespace Dms.Tests;

public class FinancialCalculatorTests
{
    [Fact]
    public void Usd_MultipliesByExchangeRate()
    {
        var result = FinancialCalculator.ComputeIqd(25000m, Currency.USD, 1310m);
        Assert.Equal(32_750_000m, result);
    }

    [Fact]
    public void Iqd_ReturnsAmountAsIs()
    {
        var result = FinancialCalculator.ComputeIqd(5_000_000m, Currency.IQD, null);
        Assert.Equal(5_000_000m, result);
    }

    [Fact]
    public void NullAmount_ReturnsNull()
    {
        Assert.Null(FinancialCalculator.ComputeIqd(null, Currency.USD, 1310m));
    }

    [Fact]
    public void Usd_WithoutRate_Throws()
    {
        Assert.Throws<ValidationException>(() => FinancialCalculator.ComputeIqd(100m, Currency.USD, null));
    }

    [Fact]
    public void Usd_WithZeroRate_Throws()
    {
        Assert.Throws<ValidationException>(() => FinancialCalculator.ComputeIqd(100m, Currency.USD, 0m));
    }

    [Fact]
    public void Amount_WithoutCurrency_Throws()
    {
        Assert.Throws<ValidationException>(() => FinancialCalculator.ComputeIqd(100m, null, null));
    }

    [Fact]
    public void Usd_RoundsToTwoDecimals()
    {
        var result = FinancialCalculator.ComputeIqd(10m, Currency.USD, 1310.555m);
        Assert.Equal(13105.55m, result);
    }
}
