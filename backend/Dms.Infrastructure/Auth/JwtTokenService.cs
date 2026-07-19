using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Dms.Domain;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace Dms.Infrastructure.Auth;

/// <summary>أسماء الـ Claims المخصّصة داخل الـ JWT.</summary>
public static class DmsClaims
{
    public const string UserId = "uid";
    public const string CompanyIds = "cids";
    public const string CanApprove = "approve";
    public const string Role = "role";
    public const string Modules = "mods";
}

public sealed record TokenPair(string AccessToken, DateTime AccessExpires, string RefreshToken, DateTime RefreshExpires);

public interface IJwtTokenService
{
    TokenPair Create(User user);
    string HashRefreshToken(string refreshToken);
}

public sealed class JwtTokenService(IOptions<JwtSettings> options) : IJwtTokenService
{
    private readonly JwtSettings _s = options.Value;

    public TokenPair Create(User user)
    {
        var now = DateTime.UtcNow;
        var accessExpires = now.AddMinutes(_s.AccessTokenMinutes);

        var claims = new List<Claim>
        {
            new(DmsClaims.UserId, user.UserId.ToString()),
            new(ClaimTypes.NameIdentifier, user.UserId.ToString()),
            new(ClaimTypes.Name, user.Username),
            new(DmsClaims.Role, user.Role.ToString()),
            new(ClaimTypes.Role, user.Role.ToString()),
            new(DmsClaims.CanApprove, user.CanApprove ? "1" : "0"),
            new(DmsClaims.Modules, ((int)user.Modules).ToString()),
        };
        if (user.AssignedCompanies.Any())
        {
            var ids = string.Join(",", user.AssignedCompanies.Select(c => c.CompanyId));
            claims.Add(new Claim(DmsClaims.CompanyIds, ids));
        }

        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_s.SigningKey));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var jwt = new JwtSecurityToken(
            issuer: _s.Issuer,
            audience: _s.Audience,
            claims: claims,
            notBefore: now,
            expires: accessExpires,
            signingCredentials: creds);

        var access = new JwtSecurityTokenHandler().WriteToken(jwt);

        var refresh = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        var refreshExpires = now.AddDays(_s.RefreshTokenDays);

        return new TokenPair(access, accessExpires, refresh, refreshExpires);
    }

    public string HashRefreshToken(string refreshToken)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(refreshToken));
        return Convert.ToBase64String(bytes);
    }
}
