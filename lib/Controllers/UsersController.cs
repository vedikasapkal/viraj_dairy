[Route("api/[controller]")]
[ApiController]
public class UsersController : ControllerBase
{
    private readonly DairyDbContext _context;

    public UsersController(DairyDbContext context)
    {
        _context = context;
    }

    // GET: api/users (For Admin to see all customers/delivery boys)
    [HttpGet]
    public async Task<ActionResult<IEnumerable<User>>> GetUsers()
    {
        return await _context.Users.ToListAsync();
    }

    // POST: api/users/login-or-register (For Customer / Delivery Login)
    [HttpPost("login-or-register")]
    public async Task<ActionResult<User>> LoginOrRegister(UserDto dto)
    {
        var user = await _context.Users.FirstOrDefaultAsync(u => u.Mobile == dto.Mobile);
        if (user == null)
        {
            user = new User { Name = dto.Name, Mobile = dto.Mobile, Address = dto.Address, Role = dto.Role };
            _context.Users.Add(user);
            await _context.SaveChangesAsync();
        }
        return Ok(user);
    }
}