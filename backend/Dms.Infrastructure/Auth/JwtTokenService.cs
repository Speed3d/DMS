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
    public const string Role = "role";

    // ↓ سبعتها **خرائط لكل شركة** بصيغة PerCompanyClaim (ADR-017)، لا قيماً مفردة.
    public const string CanApprove = "approve";
    public const string Modules = "mods";
    public const string CanManageIncoming = "inc_mng";
    public const string CanViewAllIncoming = "inc_all";

    // ⚠️ حلّا محلّ `hr_mng` الواحدة (ADR-025). **التوكنات القديمة تفقدهما فتُقرأ `null`**،
    //    ومعناه «لا صلاحية» — فشلٌ **مغلق** لا مفتوح، يزول عند أول تجديدٍ للتوكن.
    public const string CanManageEmployees = "emp_mng";
    public const string CanManagePayroll = "pay_mng";

    /// <summary>تعديل شهرٍ مُسدَّد (ADR-026).</summary>
    public const string CanAmendPaidPayroll = "pay_amend";

    public const string DepartmentId = "dept";
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
        };

        // الصلاحيات والقسم تختلف باختلاف الشركة (ADR-017) ⇒ تُرمَّز خرائطَ «شركة:قيمة».
        var links = user.AssignedCompanies.ToList();
        if (links.Count > 0)
        {
            claims.Add(new Claim(DmsClaims.CompanyIds, string.Join(",", links.Select(c => c.CompanyId))));
            claims.Add(new Claim(DmsClaims.Modules,
                PerCompanyClaim.Encode(links.ToDictionary(c => c.CompanyId, c => (int)c.Modules))));
            claims.Add(new Claim(DmsClaims.CanApprove,
                PerCompanyClaim.Encode(links.ToDictionary(c => c.CompanyId, c => c.CanApprove ? 1 : 0))));
            claims.Add(new Claim(DmsClaims.CanManageIncoming,
                PerCompanyClaim.Encode(links.ToDictionary(c => c.CompanyId, c => c.CanManageIncoming ? 1 : 0))));
            claims.Add(new Claim(DmsClaims.CanViewAllIncoming,
                PerCompanyClaim.Encode(links.ToDictionary(c => c.CompanyId, c => c.CanViewAllIncoming ? 1 : 0))));
            claims.Add(new Claim(DmsClaims.CanManageEmployees,
                PerCompanyClaim.Encode(links.ToDictionary(c => c.CompanyId, c => c.CanManageEmployees ? 1 : 0))));
            claims.Add(new Claim(DmsClaims.CanManagePayroll,
                PerCompanyClaim.Encode(links.ToDictionary(c => c.CompanyId, c => c.CanManagePayroll ? 1 : 0))));
            claims.Add(new Claim(DmsClaims.CanAmendPaidPayroll,
                PerCompanyClaim.Encode(links.ToDictionary(c => c.CompanyId, c => c.CanAmendPaidPayroll ? 1 : 0))));

            // القسم اختياري — تُدرَج الشركات التي له فيها قسم فقط.
            var depts = links.Where(c => c.DepartmentId is not null)
                             .ToDictionary(c => c.CompanyId, c => c.DepartmentId!.Value);
            if (depts.Count > 0)
                claims.Add(new Claim(DmsClaims.DepartmentId, PerCompanyClaim.Encode(depts)));
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
